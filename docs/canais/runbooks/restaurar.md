# Runbook: restaurar a pilha de canais

Scripts em `vps_rt_infra/stacks/canais/scripts/` (branch `feat/fase-ch-canais`). **Sempre ensaiar com `--teste` antes de `--aplicar`.**

## O que existe de backup
- Antes de cada atualizacao: `backup-before-upgrade.sh` -> `/opt/platform/data/canais/backups/<ts>/` (dumps de `synapse`, `mautrix_meta`, `mautrix_instagram`, `mautrix_whatsapp`; `arquivos.tgz` com Synapse, bridges e sessoes TikTok; `versions.env.anterior`; digests em execucao; `SHA256SUMS`).
- Diario: `backup.sh` (restic -> Drive) inclui `canais-matrix-postgres` e os diretorios de dados.

## Ensaio (nao toca producao)
```
restore.sh /opt/platform/data/canais/backups/<ts> --teste
```
Restaura os 4 dumps num Postgres descartavel (sem rede), confere tabelas e remove o container.

## Restauracao real
1. Avisar o dono; escolher o backup (o do momento imediatamente anterior ao problema).
2. Parar a pilha: `docker compose -p canais stop` (a fila do gateway segura as saidas; nenhum dado e apagado).
3. `RESTORE_PILHA_PARADA=1 restore.sh <backup> --aplicar` e digitar `RESTAURAR`.
   - O estado atual vai para `quarentena/<ts>/` e os bancos antigos viram `*_pre_restore_*` (nada e apagado).
4. Subir por release (`apply-stack.sh canais`), nunca `docker run` na mao.
5. Conferir: `docker ps` saudavel; login do bridge preservado (`GET /logins`); uma mensagem entra e sai em conta de teste; gateway reconverge (estados `connected`).
6. Se o login nao sobreviveu (sessao expirada no provedor): estado `reauth_required` e usar `reconectar.md`.

## Perda de volume (sem backup util)
Conexoes viram `reauth_required`; o historico oficial esta no Chatwoot (nao no Matrix); reconectar pelo assistente.

## Apos o incidente
Registrar tempo de restauracao no log da fase; repetir o ensaio `--teste` no mes seguinte (parte do ciclo mensal).
