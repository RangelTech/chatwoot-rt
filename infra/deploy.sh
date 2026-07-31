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
    --set-env-vars="PORT=8100,CHATWOOT_BASE_URL=$(chatwoot_url),AGENT_PLATFORM_URL=$(agent_platform_url)" \
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
    --set-secrets=POSTGRES_PASSWORD=chatwoot-db-password:latest,SECRET_KEY_BASE=chatwoot-secret-key-base:latest,REDIS_URL=chatwoot-redis-url:latest \
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
    --set-secrets=POSTGRES_PASSWORD=chatwoot-db-password:latest,SECRET_KEY_BASE=chatwoot-secret-key-base:latest,REDIS_URL=chatwoot-redis-url:latest \
    --set-env-vars="$(chatwoot_env)" \
    --command=/usr/local/bin/rt-web.sh \
    --allow-unauthenticated \
    --memory=2Gi --cpu=2 --min-instances=1 --max-instances=5 \
    --timeout=600 --port=3000

  # Sidekiq com min-instances=1: fila parada é atendimento parado.
  gcloud run deploy chatwoot-worker \
    --project=$PROJECT --region=$REGION \
    --image=$REPO/chatwoot-rt:$SHORT_SHA \
    --service-account=$RUNTIME_SA \
    --set-secrets=POSTGRES_PASSWORD=chatwoot-db-password:latest,SECRET_KEY_BASE=chatwoot-secret-key-base:latest,REDIS_URL=chatwoot-redis-url:latest \
    --set-env-vars="$(chatwoot_env)" \
    --command=/usr/local/bin/rt-worker.sh \
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
FRONTEND_URL=${frontend}
ACTIVE_STORAGE_SERVICE=s3_compatible
S3_BUCKET_NAME=chatwoot
STORAGE_REGION=us-east-1
STORAGE_ENDPOINT=https://storage.rangeltech.net
STORAGE_FORCE_PATH_STYLE=true
ENABLE_ACCOUNT_SIGNUP=false
EOF
}

case $target in
  bridge) deploy_bridge ;;
  chatwoot) deploy_chatwoot ;;
  migrate) migrate_chatwoot ;;
  all) migrate_chatwoot; deploy_chatwoot; deploy_bridge ;;
  *) echo "usage: $0 [bridge|chatwoot|migrate|all]" >&2; exit 1 ;;
esac
