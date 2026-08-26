#!/usr/bin/env bash
# Deploy da bridge (FastAPI) pro Cloud Run, projeto rangel-tech.
#
# infra-01 seção 5 (mega-spec-reestrutura): `infra/deploy.sh` original (este
# repo) já tinha todo o desenho de deploy pro Cloud Run, só que apontava pro
# projeto errado (eduk-prd-lake, é da MindLab/Eduk, outro cliente do dono).
# Este script foca só na bridge (a peça mais simples e menos arriscada de
# migrar primeiro) — chatwoot-web/worker (Rails, min_instances=1, precisa de
# migration job) ficam pro `infra/deploy.sh` original ainda, corrigido depois
# numa fatia separada.
#
# DATABASE_URL aponta pro Postgres real da VPS via porta 5433
# (postgres-direct, TLS) — mesmo achado do litellm-router/kernel-llm/backend:
# 5432 (PgBouncer) não faz TLS server-side.
set -euo pipefail

PROJECT=rangel-tech
REGION=us-central1
REPO=us-central1-docker.pkg.dev/$PROJECT/containers

cd "$(dirname "$0")/.."
SHORT_SHA=$(git rev-parse --short HEAD)
GCLOUD_BIN=${GCLOUD_BIN:-gcloud}

if [ -n "$(git status --porcelain --untracked-files=normal -- bridge infra)" ]; then
  echo "source tree is dirty; commit source changes before deploy" >&2
  git status --short --untracked-files=normal -- bridge infra >&2
  exit 1
fi

"$GCLOUD_BIN" builds submit --project=$PROJECT \
  --config=infra/cloudbuild-bridge.yaml \
  --substitutions=SHORT_SHA=$SHORT_SHA .

"$GCLOUD_BIN" run deploy chatwoot-bridge \
  --project=$PROJECT --region=$REGION \
  --image=$REPO/chatwoot-rt-bridge:$SHORT_SHA \
  --set-secrets=DATABASE_URL=chatwoot-bridge-database-url:latest,ENCRYPTION_KEY=chatwoot-bridge-encryption-key:latest,BRIDGE_ADMIN_TOKEN=chatwoot-bridge-admin-token:latest,CHATWOOT_PLATFORM_TOKEN=chatwoot-platform-token:latest,EVOLUTION_SSH_PRIVATE_KEY=chatwoot-bridge-evolution-ssh-key:latest \
  --set-env-vars="CHATWOOT_BASE_URL=https://chat.rangeltech.net,AGENT_PLATFORM_URL=https://ia.rangeltech.net,ENVIRONMENT=production" \
  --allow-unauthenticated \
  --memory=512Mi --cpu=1 --min-instances=0 --max-instances=5 \
  --timeout=600 --port=8100
# TEMPORÁRIO (25->26/08/2026, madrugada): min=0 pra economizar custo durante
# execução autônoma noturna sem tráfego real, pedido explícito do dono.
# Valor de produção de verdade é min-instances=1 (decisão 24/08/2026, cold
# start deixa de ser aceitável -- 4,7s medido em GET /health, achado
# 23/08/2026. Bridge está no caminho de toda mensagem de saída real
# (Chatwoot -> Agent Bot -> bridge -> provedor)) -- REVERTER pra
# min-instances=1 antes de qualquer tráfego de cliente voltar. Registrado em
# memoria.md. Confirmado antes de editar: este é o
# único workflow que deploya chatwoot-bridge neste repo (sem a armadilha
# de 2 caminhos competindo achada no kernel-llm).

# BRIDGE_PUBLIC_URL vira o outgoing_url de todo Agent Bot (é o webhook que o
# Chatwoot chama a cada mensagem nova -- sem isso resolver, a IA nunca vê a
# mensagem). Achado real 23/08/2026: "https://bridge.rangeltech.net" está no
# DNS mas ainda aponta pro IP antigo da VPS (66.94.101.153), de antes da
# bridge migrar pro Cloud Run (infra-01) -- Traefik lá responde 404 (rota
# nunca existiu pra bridge, só chat/ia ganharam proxy reverso pro Cloud Run
# na migração). Até alguém configurar esse proxy reverso (ou um domain
# mapping do Cloud Run) meia URL morta é pior que a URL real do Cloud Run:
# usar sempre a URL viva do próprio serviço.
BRIDGE_URL=$("$GCLOUD_BIN" run services describe chatwoot-bridge \
  --project=$PROJECT --region=$REGION --format='value(status.url)')
"$GCLOUD_BIN" run services update chatwoot-bridge \
  --project=$PROJECT --region=$REGION \
  --update-env-vars="BRIDGE_PUBLIC_URL=$BRIDGE_URL"
