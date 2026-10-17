# infra

Este repo nao faz deploy. O release (`.github/workflows/release.yml`, tag `v*`) publica dois
servicos como docker-archive + manifesto; quem implanta e so o `vps_rt_infra`.

| Servico | Assets | Healthcheck | Compose (stack `chatwoot`) |
|---|---|---|---|
| `chatwoot-rails` | `chatwoot-rails.image.tar.gz`, `release-manifest.chatwoot-rails.json` | `GET /health` porta 3000, timeout 240s | `chatwoot-web`, `chatwoot-worker`, one-shot `chatwoot-migrate` (pre_deploy) |
| `chatwoot-bridge` | `chatwoot-bridge.image.tar.gz`, `release-manifest.chatwoot-bridge.json` | `GET /health` porta 8100 | `bridge` |

## Uma imagem Rails, tres papeis

| Servico compose | command | Observacao |
|---|---|---|
| `chatwoot-web` | `./rt-web.sh` (default da imagem) | `rails server` em `$PORT` (3000) |
| `chatwoot-worker` | `./rt-worker.sh` | Sidekiq; sobe tambem um responder TCP em `$PORT` (so legado Cloud Run, inofensivo) |
| `chatwoot-migrate` | `bundle exec rails db:chatwoot_prepare` | one-shot, antes do `up`; nunca no boot |

Os tres usam o mesmo env (`env.required` do manifesto + opcionais abaixo). `SECRET_KEY_BASE` igual em web e worker.

## HEALTHCHECK do worker

A imagem declara `HEALTHCHECK CMD /app/rt-healthcheck.sh`, herdado pelo worker. O script
(`chatwoot/entrypoints/healthcheck.sh`) decide pelo processo: se existe processo `sidekiq`
(`pgrep -f sidekiq`) responde saudavel; senao faz `wget http://127.0.0.1:${PORT:-3000}/health`.
Assim web e worker usam o mesmo healthcheck sem env nem flag, e o worker nao falha por nao ter HTTP.
Se o sidekiq morrer o container sai (exec) e o restart policy age. O `chatwoot-migrate` e one-shot e nao usa healthcheck.

## Usuario e variaveis

- Rails e bridge rodam como uid 10001 (nao-root). `GIT_COMMIT` vem como build-arg.
- Referencia de nomes: `infra/.env.prod.chatwoot.example`, `infra/env/*.env.example`.
  Storage S3 compativel (MinIO): `ACTIVE_STORAGE_SERVICE=s3_compatible`, `STORAGE_ENDPOINT=http://minio:9000`,
  `STORAGE_FORCE_PATH_STYLE=true`, `AWS_REQUEST_CHECKSUM_CALCULATION=when_required`, `AWS_RESPONSE_CHECKSUM_VALIDATION=when_required`.
- Pos-deploy opcional: `rails runner scripts/ops/...` (bootstrap_platform, locale_pt_br) e `rake installation_config:sync_meta`.
