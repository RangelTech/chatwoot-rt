# Runbook: atualização mensal do Chatwoot (Fase UP)

Ciclo mensal: acompanhar a última versão **estável** do upstream, mesclar, ensaiar e colocar em
produção uma vez por mês. Versão **maior** (ex.: 5.x) não entra no ciclo: vira projeto próprio.
A pasta `chatwoot/enterprise/` não é editada, carregada nem apagada (mesclagem aceita o upstream).
Correção de segurança crítica pode antecipar o ciclo.

## Peças

| Peça | Onde |
| --- | --- |
| Contrato de extensões | `chatwoot/fork_extensions.yml` + `scripts/verify_fork_extensions.rb` |
| Código upstream exato | branch `upstream-import` (1 commit por versão, código em `chatwoot/`) |
| Importar versão | `scripts/upgrade/import_upstream.sh <X.Y.Z>` |
| Mesclar e medir | `scripts/upgrade/merge_upstream.sh <X.Y.Z> [--dry-run]` |
| Traduções | `scripts/upgrade/merge_i18n.py` (mescla por chave; chamado pela mesclagem) |
| Divergência | `python scripts/upgrade/divergence.py [--json] [--fail-on-unmarked]` |
| Suíte de contrato | `chatwoot/spec/fork_contract/CONTRACT_SPECS.txt`, `scripts/upgrade/run_contract_suite.sh`, workflow `Fork contract suite` |
| Alerta semanal | workflow `Upstream rehearsal` (segunda 09:00 UTC) e cartão "Atualização do Chatwoot" no Super Admin |

O alerta de versão aparece **só no Super Admin**. Na aplicação do usuário não há aviso. A verificação
diária (`Rt::UpstreamVersionCheckJob`) lê apenas a lista pública de lançamentos; nada da instalação sai.
Telemetria: `DISABLE_TELEMETRY=true` (também forçado por `config/initializers/rt_telemetry.rb`).

## Calendário

1. **Semana 1**: branch `upgrade/<versão>`, mesclagem e testes automáticos.
2. **Semana 2**: ensaio em cópia do banco (compose descartável) + CDP rápido.
3. **Semana 3**: canário em Account de teste.
4. **Semana 4**: produção (fora de pico) + vigilância de 7 dias.

Registrar cada ciclo no §12 da spec: conflitos, horas, regressões.

## Passo a passo

1. **Importar o upstream**: `bash scripts/upgrade/import_upstream.sh 4.17.0`. Confere `VERSION_CW` do tag.
2. **Branch**: `bash scripts/upgrade/merge_upstream.sh 4.17.0` (cria `upgrade/4.17.0` a partir do ponto atual e mescla).
   - Traduções (`*.json` de locale): mescladas por chave, marca reaplicada, 0 conflito manual.
   - `config/locales/*.yml` e `enterprise/**`: aceita o upstream.
   - O resto que conflitar é a lista de pontos de contato: resolver olhando o marcador do contrato.
3. **Atualizar a versão**: `chatwoot/fork_extensions.yml: upstream_version` deve igualar `chatwoot/VERSION_CW`
   (o verificador falha se divergir).
4. **Contrato**: `ruby scripts/verify_fork_extensions.rb` e `python scripts/upgrade/divergence.py --fail-on-unmarked`.
5. **Testes**: suíte de contrato (`run_contract_suite.sh`), specs do upstream (completas no CI ou por fatias),
   `pnpm vitest`/`eslint`, `rails rt:brand:verify`.
6. **Backup e restauração testada**: `pg_dump` do banco de produção, restaurar em PG descartável, rodar as
   migrações **na cópia** (medir tempo e bloqueios). Migração do upstream é tratada como **sem volta**.
7. **Imagem nova e ensaio**: compose descartável com a cópia do banco; CDP rápido (blocos LG, P, C, FQ, N, M, V).
8. **Canário** em Account de teste.
9. **Produção por release (K-10)**: drenar o worker antes de trocar; nunca trocar contêiner na mão.
   Rollback de imagem = `previous_version` do lock. Rollback de dados = restaurar o backup tirado
   imediatamente antes.
10. **Vigilância de 7 dias** e regressão rápida (CDP L, P, C, F, N, M, V + suíte de contrato).

## Quando a mesclagem trava

- Ponto de contato sem marcador: adicionar ao `fork_extensions.yml` (extensão certa) com um marcador estável.
- Tradução com chave removida no upstream: some do fork também, exceto chaves só do fork (ragent, kanban).
- Arquivo de marca (`brand_luar_touchpoints`): aceitar o upstream e reaplicar a marca; o marcador prova que voltou.
- Mais de 2 dias de esforço numa versão menor: ajustar o processo e registrar no §12.

## Rollback do ensaio local

`git merge --abort` (ou `git switch main && git branch -D upgrade/<versão>`); nada é empurrado por esses scripts.
