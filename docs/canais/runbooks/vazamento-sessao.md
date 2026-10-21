# Runbook: suspeita de vazamento de sessao ou credencial

Uma sessao (do bridge ou do worker TikTok) equivale a uma credencial. O Luar **nao** recebe nem guarda cookie/senha/token de sessao; o risco esta nos bancos dos bridges, nos diretorios de sessao do TikTok, nos tokens do appservice e em logs.

## 1. Conter (primeiros minutos)
1. Identificar o escopo: um `connection_id`, um tenant, ou a pilha toda?
2. **Revogar** as conexoes afetadas (`revogar.md`); para a pilha toda: parar `mautrix-*` e workers (`docker compose -p canais stop`), preservando volumes.
3. Registrar o horario e quem decidiu (`rt_channel_audit`).

## 2. Girar segredos
Gerar novos valores (`openssl rand -hex 32`) em `/opt/platform/secrets/canais.env`, **todos de uma vez** se o escopo for incerto: `BRIDGE_PROVISIONING_SECRET`, `*_AS_TOKEN`/`*_HS_TOKEN` (bridges e gateway), `CHANNELS_GATEWAY_TOKEN`, segredos de webhook por conexao, `MATRIX_POSTGRES_PASSWORD`, segredos do Synapse. Rodar `render-configs.sh` e subir por release. Como o bridge reaprende o appservice pelo registro renderizado, sem editar a mao.

## 3. Pedir ao dono da conta no provedor
Encerrar sessoes ativas, trocar a senha, revisar dispositivos conectados. Sem isso a sessao vazada pode continuar valida no provedor.

## 4. Investigar
Procurar por segredo em logs/telemetria/Sidekiq/APM/DOM (a regra e: nenhum). Conferir `filter_parameters` (`password`, `data`, `code`, `verification_code`). Checar acessos entre tenants (autorizacao negativa) e logs de `GET /logins` fora do gateway.

## 5. Recuperar
Reconectar pelo assistente (`reconectar.md`) apos girar segredos. Historico e conversas permanecem.

## 6. Comunicar
LGPD: avaliar incidente de seguranca com dado pessoal; se houver risco relevante, comunicar titulares e ANPD no prazo legal (ver `RETENCAO_E_CONSENTIMENTO.md`). Decisao e texto: do dono/DPO.

## 7. Fechar
Pos-mortem sem segredos; ajustar redacao de logs, permissoes e este runbook.
