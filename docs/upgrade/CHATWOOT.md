# Manual de atualização do Chatwoot (fork luar_chatwoot)

Atualização **manual, uma vez por mês**. Contrato geral em `CONTRATO.md`. Este manual complementa `docs/architecture/fork-maintenance.md`.

## Pré-condições
1. Janela marcada (primeira terça), outros deploys congelados, `DISABLE_TELEMETRY=true` ativo.
2. Backup do banco do Chatwoot e **restauração testada** em PostgreSQL descartável.
3. Changelog do upstream lido; alvo decidido (ex.: 4.16.2 → 4.17.0).

## Passos
1. Branch `upstream-import` com a tag oficial na subpasta `chatwoot/`; gerar o inventário de divergência.
2. Branch `upgrade/<versão>` a partir do `main`; mesclar `upstream-import`.
3. Conflitos: **traduções** (`i18n/locale/*.json`): aceitar o upstream e reaplicar a marca (`rt:brand:apply`, idempotente); **pontos de contato** pelos marcadores de `fork_extensions.yml`; `enterprise/`: aceitar o upstream.
4. Portões: `verify_fork_extensions`, suíte de contrato do fork (rspec e vitest), `rt:brand:verify`, lint.
5. **Ensaio** com cópia do banco: migrações com tempo e bloqueios medidos; migrações do upstream são tratadas como **sem volta**.
6. **Canário** em conta de teste: CDP rápido (login, menus IA e Configurações, caixas de entrada oficiais/não oficiais, filas, Kanban, chat com IA, Super Admin com campo de plano).
7. Release oficial → intake → deploy `chatwoot-rails` e `chatwoot-bridge`. Rollback de imagem: digest anterior; rollback de dados: restauração do backup do passo 2.
8. Vigilância por 7 dias.

## Abortar se
falhar isolamento entre contas, permissões `ai.*`, ciclo de vida (suspender/retomar) ou marca; ou se a migração não tiver volta e o backup não estiver validado.

## Registro do 1º upgrade real: 4.16.2 → 4.17.1 (23/10/2026)
- **Método usado** (sem os scripts de `scripts/upgrade/`, direto em cópia): clone do upstream, `base` = tag 4.16.2, `ours` = nossa pasta `chatwoot/` do `main` sobre a base, `trial` = tag 4.17.1, `git merge ours`. Resultado: **562 arquivos nossos**, **9 arquivos com conflito (10 blocos)**.
- **Conflitos e decisão:** `accounts_controller.rb` (nosso: sem aviso de versão), `Sidebar.vue` (nosso: menu IA do Luar no lugar dos itens do Captain), `routes.rb` e `busEvents.js` (manter os dois lados), `auditLogs.json`, `integrations.json`, `pt_BR.yml` (upstream + marca LUAR), `Whatsapp.vue` (upstream + nossa mensagem de configuração incompleta e o teste `hasWhatsappConfigurationId`), `schema.rb` (versão mais nova).
- **Armadilhas:** (1) o `git archive` do repositório do Luar converte para CRLF por causa de `core.autocrlf`; usar `git -c core.autocrlf=false archive HEAD:chatwoot`, senão aparecem milhares de conflitos falsos. (2) O upstream trouxe textos novos com "Chatwoot" (20 linhas em 4 arquivos de i18n, pt-BR e en): trocar por "LUAR" ou `rt:brand:verify` falha. (3) Atualizar `upstream_version` em `fork_extensions.yml` e a versão do README, ou o contrato do fork falha.
- **Portões:** contrato do fork, rspec (184), vitest e ponte passaram no CI. Backup do banco antes do deploy: `/opt/platform/backups/chatwoot_prod_pre_v417_*.dump`.
- **Tempo real:** ensaio e resolução ~1 h; build da imagem do Rails ~31 min no CI.
- **Depois do deploy:** `/api` responde `4.17.1`; QA de API 26/26; Sr Moon usando o PC pelo chat; front do app por CDP.
