# Runbook: desconectar / revogar uma conexao

**Desconectar** = o cliente quer parar (logout no bridge, sessao removida, estado `disconnected`, historico preservado).
**Revogar** = suspeita de uso indevido, saida de funcionario, fim de contrato ou vazamento (estado `revoked`; nao reconecta sem nova autorizacao e novo consentimento).

## Usuario (admin da conta)
Caixa de entrada -> **Desconectar** (ou **Revogar**). O Luar chama `POST /internal/channels/connections/{id}/disconnect|revoke` no gateway, que faz o *logout* no bridge e apaga a sessao. Nada mais precisa ser feito.

## Operador (se o botao falhar ou a conta foi desligada)
1. Confirmar o tenant e o `connection_id` (tabela `rt_channel_connections`; a consulta filtra por `account_id`).
2. Chamar `revoke` pelo gateway (interno). Estado esperado: `revoked`.
3. Conferir no bridge: `GET /_matrix/provision/v3/logins` do usuario `@luar_t<conta>_c<id>` sem logins.
4. TikTok: parar o worker da conta e **mover** o diretorio de sessao para quarentena (`tiktok-sessions/<conta>` -> `quarentena/`), sem apagar; apagar so apos o prazo de retencao e com backup/aceite.
5. Pedir ao dono da conta que, no aplicativo do provedor, **encerre sessoes ativas e troque a senha** (a revogacao do lado do provedor e dele).
6. Registrar em `rt_channel_audit` (ator, motivo, sem segredos).

## Verificacoes
- 0 mensagens novas entram depois do `revoked`; envio devolve erro claro.
- Conversas e historico continuam legiveis no Chatwoot (nunca apagar dado automaticamente).
- Se foi suspeita de vazamento: seguir tambem `vazamento-sessao.md`.
