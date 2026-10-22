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
