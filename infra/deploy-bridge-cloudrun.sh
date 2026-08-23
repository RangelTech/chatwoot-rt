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
  --set-env-vars="CHATWOOT_BASE_URL=https://chat.rangeltech.net,AGENT_PLATFORM_URL=https://ia.rangeltech.net,BRIDGE_PUBLIC_URL=https://bridge.rangeltech.net,ENVIRONMENT=production" \
  --allow-unauthenticated \
  --memory=512Mi --cpu=1 --min-instances=0 --max-instances=5 \
  --timeout=600 --port=8100
