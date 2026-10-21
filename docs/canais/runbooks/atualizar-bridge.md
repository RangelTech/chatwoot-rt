# Runbook: atualizar bridge (mautrix) e ReLttk — ciclo mensal (Fase UP)

**Principio:** versoes **fixadas** (tag + digest), nunca `latest`. Atualiza-se conferindo changelog, testando em conta de teste e so entao promovendo. Os bridges e o ReLttk seguem protocolos que mudam rapido: atrasar demais tambem quebra.

## Calendario
Semana 1: conferir versoes novas e ler changelog. Semana 2: ensaio em conta de teste. Semana 3: promover (janela curta, sem pico). Semana 4: vigilancia e registro no log da fase (metrica: horas, regressoes).

## Passos
1. **Ler**: changelog de `mautrix/meta` (Messenger e Instagram `ig-`), `mautrix/whatsapp`, Synapse, e commits do `Linkmail16/ReLttk-TikTok-Client-Bot` desde o commit fixado. Procurar: mudanca de modo de login, migracao de banco do bridge (**sem volta**), nova chave de config, alteracao de licenca.
2. **Licenca**: continuar usando as imagens sem modificar (AGPL-3.0). Se algo exigir alterar o codigo, parar e decidir com o dono (AGPL §13). ReLttk e MIT.
3. **Fixar**: editar a tag em `stacks/canais/versions.env` (marcador `DIGEST_A_PREENCHER`), rodar `scripts/resolve_digests.sh`, revisar o diff.
4. **Validar**: `stacks/canais/scripts/validate.sh --strict`; atualizar `docs/canais/MATRIZ_VERSOES.md`.
5. **Backup**: `backup-before-upgrade.sh` e `restore.sh <backup> --teste` (restore ensaiado e requisito).
6. **Ensaio**: subir a pilha numa copia descartavel (compose de teste) com a copia do banco e **conta de teste**: login (senha/QR), 2FA, mensagem nos dois sentidos, reconexao.
7. **Promover**: por release/lock (K-10): drenar o gateway (sem envio em voo; a *outbox* segura), `apply-stack.sh canais`, aguardar healthchecks. Nunca trocar container na mao.
8. **Conferir**: `docker ps` saudavel; conexoes continuam `connected`; metricas (atraso, duplicatas, reautenticacoes) sem salto; 0 vazamento nos logs.
9. **Rollback**: imagem = `rollback.sh`; dados (migracao sem volta) = `restore.sh <backup> --aplicar`.
10. **Registrar**: data, versoes antes/depois, conflitos, horas, regressoes.

## ReLttk (TikTok)
- A imagem do worker fixa o **commit** do ReLttk. Atualizar = novo commit + novo build + novo digest.
- Conferir a **dependencia de assinatura** (signer local/offline vs servico externo): se mudar, reabrir a avaliacao de risco.
- Testar em conta de teste: QR, 2FA, reconexao, texto nos dois sentidos, memoria do worker. Workers sobem **um por conta**; trocar um por vez.
- Se o ReLttk quebrar com mudanca do TikTok: ver `provedor-muda.md` (canal vai a `degraded`/`reauth_required`; nao tentar contornar).
