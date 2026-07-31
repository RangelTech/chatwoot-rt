#!/usr/bin/env bash
# Deploy do ecossistema omnichannel no Cloud Run (projeto eduk-prd-lake).
#
# Espelha o padrão do agent-platform: build por workload no Cloud Build,
# imagem no Artifact Registry, segredos no Secret Manager, persistência na VPS.
#
# Uso: ./infra/deploy.sh [bridge|chatwoot|migrate|all]
set -euo pipefail

PROJECT=eduk-prd-lake
REGION=us-central1
REPO=us-central1-docker.pkg.dev/$PROJECT/cloud-run-source-deploy
RUNTIME_SA=devlake@eduk-prd-lake.iam.gserviceaccount.com
SHORT_SHA=$(git rev-parse --short HEAD)

target=${1:-all}
cd "$(dirname "$0")/.."

build() {
  local service=$1
  gcloud builds submit --project=$PROJECT \
    --config=infra/cloudbuild-$service.yaml \
    --substitutions=SHORT_SHA=$SHORT_SHA .
}

deploy_bridge() {
  build bridge
  gcloud run deploy chatwoot-bridge \
    --project=$PROJECT --region=$REGION \
    --image=$REPO/chatwoot-rt-bridge:$SHORT_SHA \
    --service-account=$RUNTIME_SA \
    --set-secrets=DATABASE_URL=chatwoot-bridge-database-url:latest,ENCRYPTION_KEY=chatwoot-bridge-encryption-key:latest,BRIDGE_ADMIN_TOKEN=chatwoot-bridge-admin-token:latest,CHATWOOT_PLATFORM_TOKEN=chatwoot-platform-token:latest \
    --set-env-vars="CHATWOOT_BASE_URL=$(chatwoot_url),AGENT_PLATFORM_URL=$(agent_platform_url)" \
    --allow-unauthenticated \
    --memory=512Mi --cpu=1 --min-instances=0 --max-instances=5 \
    --timeout=600 --port=8100

  # BRIDGE_PUBLIC_URL só existe depois do serviço; é ela que o Chatwoot chama
  # para devolver a resposta ao canal do cliente.
  local bridge_url
  bridge_url=$(gcloud run services describe chatwoot-bridge \
    --project=$PROJECT --region=$REGION --format='value(status.url)')
  gcloud run services update chatwoot-bridge \
    --project=$PROJECT --region=$REGION \
    --update-env-vars="BRIDGE_PUBLIC_URL=$bridge_url"
}

# Migração do Chatwoot é passo explícito: rodar isso concorrente com N
# instâncias subindo corromperia o schema.
migrate_chatwoot() {
  build chatwoot
  gcloud run jobs deploy chatwoot-migrate \
    --project=$PROJECT --region=$REGION \
    --image=$REPO/chatwoot-rt:$SHORT_SHA \
    --service-account=$RUNTIME_SA \
    --set-secrets=POSTGRES_PASSWORD=chatwoot-db-password:latest,SECRET_KEY_BASE=chatwoot-secret-key-base:latest,REDIS_URL=chatwoot-redis-url:latest,STORAGE_ACCESS_KEY_ID=teste-ia-s3-access-key:latest,STORAGE_SECRET_ACCESS_KEY=teste-ia-s3-secret-key:latest \
    --set-env-vars="$(chatwoot_env)" \
    --command=bundle --args=exec,rails,db:chatwoot_prepare \
    --max-retries=1 --task-timeout=1800 \
    --execute-now --wait
}

deploy_chatwoot() {
  build chatwoot
  gcloud run deploy chatwoot-web \
    --project=$PROJECT --region=$REGION \
    --image=$REPO/chatwoot-rt:$SHORT_SHA \
    --service-account=$RUNTIME_SA \
    --set-secrets="$(chatwoot_secrets)" \
    --set-env-vars="$(chatwoot_env)" \
    --command=./rt-web.sh \
    --allow-unauthenticated \
    --memory=2Gi --cpu=2 --min-instances=1 --max-instances=5 \
    --timeout=600 --port=3000

  # Sidekiq com min-instances=1: fila parada é atendimento parado.
  gcloud run deploy chatwoot-worker \
    --project=$PROJECT --region=$REGION \
    --image=$REPO/chatwoot-rt:$SHORT_SHA \
    --service-account=$RUNTIME_SA \
    --set-secrets="$(chatwoot_secrets)" \
    --set-env-vars="$(chatwoot_env)" \
    --command=./rt-worker.sh \
    --no-allow-unauthenticated \
    --no-cpu-throttling \
    --memory=2Gi --cpu=1 --min-instances=1 --max-instances=2 \
    --timeout=3600
}

chatwoot_url() {
  gcloud run services describe chatwoot-web --project=$PROJECT --region=$REGION \
    --format='value(status.url)' 2>/dev/null || echo ""
}

agent_platform_url() {
  gcloud run services describe teste-ia-backend --project=$PROJECT --region=$REGION \
    --format='value(status.url)' 2>/dev/null || echo ""
}

chatwoot_secrets() {
  local base="POSTGRES_PASSWORD=chatwoot-db-password:latest,SECRET_KEY_BASE=chatwoot-secret-key-base:latest,REDIS_URL=chatwoot-redis-url:latest,STORAGE_ACCESS_KEY_ID=teste-ia-s3-access-key:latest,STORAGE_SECRET_ACCESS_KEY=teste-ia-s3-secret-key:latest"
  local meta
  meta=$(meta_secrets)
  echo "${base}${meta:+,$meta}"
}

# O TLS da VPS usa certificado próprio: o tráfego é cifrado, mas a cadeia não
# é verificável publicamente. REDIS_OPENSSL_VERIFY_MODE=none é o botão que o
# próprio Chatwoot expõe para esse caso.
chatwoot_env() {
  local frontend
  frontend=$(chatwoot_url)
  cat <<EOF | tr '\n' ',' | sed 's/,$//'
RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker
RAILS_LOG_TO_STDOUT=true
POSTGRES_HOST=66.94.101.153
POSTGRES_PORT=5433
POSTGRES_DATABASE=chatwoot_prod
POSTGRES_USERNAME=chatwoot_app
POSTGRES_SSL_MODE=require
REDIS_OPENSSL_VERIFY_MODE=none
FRONTEND_URL=${frontend}
ACTIVE_STORAGE_SERVICE=s3_compatible
STORAGE_BUCKET_NAME=chatwoot
STORAGE_REGION=us-east-1
STORAGE_ENDPOINT=https://storage.rangeltech.net
STORAGE_FORCE_PATH_STYLE=true
ENABLE_ACCOUNT_SIGNUP=false
EOF
}

# Instagram e Facebook usam um único Meta App por instalação (decisão da Fase
# 2): cada tenant conecta a própria página dentro dele. Sem os segredos
# cadastrados, o deploy segue sem os canais Meta em vez de falhar.
meta_secrets() {
  local parts=""
  for pair in "FB_APP_ID=chatwoot-meta-app-id"               "FB_APP_SECRET=chatwoot-meta-app-secret"               "FB_VERIFY_TOKEN=chatwoot-meta-verify-token"               "IG_VERIFY_TOKEN=chatwoot-meta-verify-token"; do
    local env_name=${pair%%=*}
    local secret_name=${pair#*=}
    if gcloud secrets describe "$secret_name" --project=$PROJECT >/dev/null 2>&1; then
      parts="${parts:+$parts,}${env_name}=${secret_name}:latest"
    fi
  done
  echo "$parts"
}

# Cria super admin + platform app e imprime o token que a ponte usa.
bootstrap_platform() {
  build chatwoot
  gcloud run jobs deploy chatwoot-bootstrap \
    --project=$PROJECT --region=$REGION \
    --image=$REPO/chatwoot-rt:$SHORT_SHA \
    --service-account=$RUNTIME_SA \
    --set-secrets=POSTGRES_PASSWORD=chatwoot-db-password:latest,SECRET_KEY_BASE=chatwoot-secret-key-base:latest,REDIS_URL=chatwoot-redis-url:latest,STORAGE_ACCESS_KEY_ID=teste-ia-s3-access-key:latest,STORAGE_SECRET_ACCESS_KEY=teste-ia-s3-secret-key:latest,RT_SUPER_ADMIN_PASSWORD=chatwoot-super-admin-password:latest \
    --set-env-vars="$(chatwoot_env),RT_SUPER_ADMIN_EMAIL=${RT_SUPER_ADMIN_EMAIL:-admin@rangeltech.net},RT_PLATFORM_APP_NAME=rangel-bridge" \
    --command=bundle --args=exec,rails,runner,scripts/ops/bootstrap_platform.rb \
    --max-retries=1 --task-timeout=900 \
    --execute-now --wait
}

case $target in
  bridge) deploy_bridge ;;
  bootstrap) bootstrap_platform ;;
  chatwoot) deploy_chatwoot ;;
  migrate) migrate_chatwoot ;;
  all) migrate_chatwoot; deploy_chatwoot; bootstrap_platform; deploy_bridge ;;
  *) echo "usage: $0 [bridge|chatwoot|migrate|bootstrap|all]" >&2; exit 1 ;;
esac
