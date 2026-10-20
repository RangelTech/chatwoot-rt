# luar_chatwoot

O produto Luar que o cliente enxerga: caixa de entrada, conversas, Kanban, telas de IA, identidade e marca. É um fork do Chatwoot Community (versão base 4.16.2) com uma ponte própria (`bridge/`) que fala com o motor de IA e com os canais.

> Nome anterior: `chatwoot-rt`. O GitHub redireciona o endereço antigo.

## Onde ele se encaixa

```
                    Cliente (navegador e canais)
                                |
                        Traefik (VPS)
                                |
 luar_chatwoot --contexto assinado--> luar_engine --runs--> luar_harness
 (telas, inbox, Kanban,               (motor de IA:         (fila, broker,
  bridge, gateway de canais)           templates, skills,    workers Hermes)
                                       credenciais, uso)            |
                                            |                luar_workspaces
                                       luar_ai_gateway       (ambiente de cada
                                       (LLM multi-tenant)     empresa)

 vps_rt_infra: compose, releases por digest, deploy e backup (só ela implanta)
 airflow:      orquestração da empresa, inclui o backup noturno da VPS
 luar_docs:    specs, evidências e ADRs
```

É a única porta de entrada do usuário. Quem faz login, quem pode o quê e a qual empresa cada pessoa pertence é decidido aqui. O motor só aceita chamadas com contexto assinado por este repositório.

## Árvore de pastas

```
chatwoot/   fork do Chatwoot (Rails + Vue). Mantenha LICENSE e créditos; as mudanças do Luar
            ficam listadas em fork_extensions.yml para facilitar o rebase com o upstream
bridge/     serviço FastAPI: provisionamento de contas, SSO, Agent Bot (responder de IA),
            gateway de canais, idempotência e handoff IA <-> humano
infra/      exemplos de variáveis de ambiente (só os nomes)
scripts/    smoke tests e utilitários de operação
docs/       arquitetura, decisões (ADR) e runbooks
.github/    CI e release
```

## Como rodar

Ponte, em desenvolvimento:

```bash
cd bridge
pip install -r requirements.txt
cp ../infra/env/bridge.env.example .env     # preencha os valores só localmente
uvicorn app.main:app --reload --port 8100
```

O Chatwoot segue o fluxo padrão do upstream (`chatwoot/.devcontainer`).

## Como testar

- Ponte: `cd bridge && ruff check . && pytest -q`
- Chatwoot: `bundle exec rspec` (Rails) e `pnpm test` (Vue), dentro de `chatwoot/`

## Como implantar

Este repositório só produz artefatos. Uma tag `v*` dispara o release, que publica `chatwoot-rails.image.tar.gz`, `chatwoot-bridge.image.tar.gz` e um `release-manifest.<servico>.json` por serviço. Quem implanta é o `vps_rt_infra`, que lê o manifesto, fixa o digest e troca o container.

## Variáveis de ambiente

Os modelos estão em `infra/env/*.env.example`. As principais da ponte: `DATABASE_URL`, `CHATWOOT_BASE_URL`, `CHATWOOT_PLATFORM_TOKEN`, `AGENT_PLATFORM_URL`, `ENCRYPTION_KEY`, `BRIDGE_ADMIN_TOKEN`, `BRIDGE_PUBLIC_URL`. Nunca versione os valores.

## Isolamento e segurança

- Uma empresa do motor corresponde a uma `Account` do Chatwoot (`tenant.chatwoot_account_id`).
- A ponte resolve a empresa antes de qualquer leitura ou escrita.
- Credenciais de canal ficam cifradas (Fernet) por empresa.
- O repositório é público: nenhum segredo entra nele.

## Runbooks e decisões

`docs/runbooks/` (onboarding de empresa, canais Meta) e `docs/decisions/` (fronteiras, marca e planos). Manutenção do fork: `docs/architecture/fork-maintenance.md`.

## Como contribuir

Uma branch por tarefa, Conventional Commits em português, PR com CI verde. Deploy nunca sai daqui.
