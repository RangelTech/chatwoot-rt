# chatwoot-rt — operador omnichannel da Rangel Tech

Este repositório é a camada omnichannel da plataforma: ele empacota o **Chatwoot
Community** e implementa a **ponte própria** que liga o Chatwoot ao
`agent-platform` (identidade, tenants, templates e kernel de IA).

O `agent-platform` continua sendo o sistema mestre. O Chatwoot é a superfície
operacional de atendimento. A ponte é onde mora a diferenciação: provisioning,
SSO, gateway de canais, idempotência e handoff IA ↔ humano.

## Domínios internos

| Pasta | Responsabilidade |
|---|---|
| [`chatwoot/`](chatwoot/) | Empacotamento da imagem oficial + branding externo. Sem fork profundo. |
| [`bridge/`](bridge/) | Aplicação própria (FastAPI): provisioning, SSO, gateway W-API, Agent Bot. |
| [`infra/`](infra/) | Exemplos de env e nota de release/deploy (deploy so pelo vps_rt_infra). |
| [`scripts/`](scripts/) | Smoke tests e utilitários operacionais. |
| [`docs/`](docs/) | Decisões, runbooks e arquitetura local. |

## Topologia

```
canal (W-API / Meta) ─▶ bridge (gateway) ─▶ Chatwoot (API Inbox)
                                                  │
                                            Agent Bot webhook
                                                  ▼
                                    bridge ─▶ agent-platform kernel
                                                  │
                                    resposta ou handoff para humano
```

- **Compute**: VPS (stack `chatwoot`: chatwoot-web, chatwoot-worker, bridge), implantado pelo vps_rt_infra a partir dos releases.
- **Persistência**: VPS da Rangel Tech (PostgreSQL `chatwoot_prod`, Redis dedicado
  com TLS, storage MinIO). Nada de estado no Cloud Run.

## Isolamento multi-tenant

Um tenant do agent-platform corresponde a **uma** `Account` do Chatwoot, ligada por
`tenant.chatwoot_account_id`. A ponte resolve o tenant **antes** de qualquer
leitura ou escrita de estado, e toda credencial de canal é guardada por tenant.

## Como rodar a ponte localmente

```bash
cd bridge
pip install -r requirements.txt
cp ../infra/env/bridge.env.example .env
uvicorn app.main:app --reload --port 8100
```

## Release

Tag `v*` dispara `.github/workflows/release.yml`: gate da ponte (ruff + pytest), build das duas imagens
e GitHub Release com `chatwoot-rails.image.tar.gz`, `chatwoot-bridge.image.tar.gz` e um
`release-manifest.<servico>.json` por servico. O deploy e feito so pelo vps_rt_infra. Detalhes (healthcheck do
worker, papeis da imagem Rails) em [`infra/README.md`](infra/README.md).
