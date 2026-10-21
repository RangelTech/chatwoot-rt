# Contrato do gateway de canais (Fase CH)

Fonte de verdade para Rails, Vue, workers e testes. Implementação: `bridge/app/channels/`.
Rede interna apenas. Autenticação Rails -> gateway: `Authorization: Bearer <CHANNELS_GATEWAY_TOKEN>`.
`account_id` = id da conta do Chatwoot (tenant). Nenhuma resposta contém senha, cookie ou token de sessão.

## Provedores e modos de login (catálogo)
| provider | flow_id do bridge | login | observação |
|---|---|---|---|
| instagram | `android` (mautrix-instagram v26.10) | usuário+senha, 2FA, verificação | `instagram` (cookies) e `instagram-password` (webview) NUNCA usados |
| messenger | `messenger-lite` (iOS) / `messenger-lite-android` (mautrix-meta v26.10) | usuário+senha, 2FA | `facebook`/`messenger` (cookies) NUNCA usados |
| whatsapp | `qr` / `pairing-code` (mautrix-whatsapp) | QR com renovação ou código de pareamento | substitui Evolution |
| tiktok | worker ReLttk | QR (+ código de verificação) | 1 worker por conta |

## Estados (`state`)
`pending_auth`, `awaiting_2fa`, `awaiting_challenge`, `connected`, `degraded`, `reauth_required`, `disconnected`, `revoked`.
Transições válidas: ver `bridge/app/channels/states.py`.

## Endpoints (prefixo `/internal/channels`)
- `GET  /catalog` -> `{providers:[{provider, modes:[{mode:"experimental", login:"password|qr", ...}], risk_notice_version}]}`
- `POST /connections` `{account_id, provider, actor_id, consent:{accepted:true, version}, login_flow?}` -> `201 ConnectionView` + `step`. Exige `consent.accepted == true` (auditado). Limite de tentativas por conta externa/tenant (429 `too_many_attempts`).
- `POST /connections/{id}/step` `{step_id, kind, data}` -> `StepView`. **Senha e código passam só aqui, de forma síncrona; nunca por job/Sidekiq.**
- `POST /connections/{id}/cancel` -> estado `disconnected` (login não concluído).
- `GET  /connections/{id}` -> `ConnectionView` (+ `step` atual se em login, QR renovado se expirado).
- `PUT  /connections/{id}/delivery` `{webhook_url, webhook_secret, inbox_ref}` (Rails registra o destino ao finalizar; o secret nunca volta em GET).
- `POST /connections/{id}/disconnect` -> logout no bridge, remove sessão (estado `disconnected`); `POST /connections/{id}/revoke` -> `revoked`.
- `POST /connections/{id}/reauth` -> reinicia login mantendo conversas/histórico.
- `POST /connections/{id}/send` `{idempotency_key, conversation_ref, text, attachments?, reply_to?}` -> `{outbox_id, status:"queued|sent|failed", external_id?}` (idempotente por `idempotency_key`).
- `POST /connections/{id}/sync` `{since_days:60}` -> `{job_id}`; progresso em `ConnectionView.sync`.
- `GET  /connections?account_id=` -> lista (somente do tenant). Acesso a conexão de outro `account_id` = `404`.
- `GET  /attachments/{token}` -> download por URL assinada (expira).
- `POST /bridge/events` (Matrix appservice/worker -> gateway, autenticado por token próprio) – interno.

### ConnectionView
`{id, account_id, provider, mode:"experimental", state, external_label, last_activity_at, last_error_code, connector_version, sync:{status, progress, since_days}, health:{process, session, io}}`

### StepView
```
{state, step: {step_id, kind, instructions_key,
   fields:[{id, type:"username|password|2fa_code|text", label_key, secret:bool}],
   qr:{data, expires_at, refresh_after_s}, pairing_code, wait:{poll_after_s, can_cancel},
   error_code?, attempts_left?}}
```
`kind`: `credentials`, `code_2fa`, `await_approval`, `qr`, `pairing_code`, `syncing`, `complete`.
`error_code` (traduzido no front): `wrong_password`, `wrong_code`, `account_locked`, `checkpoint_required`, `timeout`, `too_many_attempts`, `provider_unavailable`, `unsupported_step`.

## Evento normalizado gateway -> Rails (webhook assinado)
`POST {webhook_url}` cabeçalhos: `X-Luar-Event-Id`, `X-Luar-Timestamp` (epoch s), `X-Luar-Signature: sha256=<hex>` onde
`hex = HMAC_SHA256(webhook_secret, "<timestamp>.<corpo bruto>")`. Rails rejeita se |agora - ts| > 300 s, assinatura inválida, ou `event_id` repetido (replay).
```
{ "event_id": "...", "type": "message.created|message.status|connection.state",
  "account_id": 1, "connection_id": "uuid", "channel": "instagram|messenger|whatsapp|tiktok",
  "provider_mode": "experimental", "occurred_at": "ISO8601",
  "conversation": {"external_id": "...", "contact": {"external_id":"...", "name":"...", "username":"...", "avatar_url":null}},
  "message": {"external_id":"...", "direction":"incoming|outgoing_echo", "text":"...", "sent_at":"ISO8601",
              "reply_to":null, "attachments":[{"kind":"image|video|audio|file","mime":"...","name":"...","url":"<url assinada do gateway>"}]},
  "state": {"state":"degraded","error_code":"..."}   // só em connection.state
}
```
Idempotência de entrada: `source_id` no Chatwoot = `message.external_id`; chave única `(account_id, connection_id, external_id)`. Eco de mensagem enviada por nós (`outgoing_echo`) não gera mensagem duplicada.

## Tabelas do gateway (Postgres da bridge; sem segredos)
`rt_channel_connections`, `rt_channel_rooms`, `rt_channel_messages`, `rt_channel_audit`, `rt_channel_outbox`, `rt_channel_dead_letter`.

## BFF Rails (navegador -> Rails), prefixo `/api/v1/accounts/:account_id/channel_connections`
Somente administradores da conta. Rails repassa ao gateway de forma síncrona (senha/código nunca vão a job, `filter_parameters` cobre `password`, `data`, `code`, `verification_code`).
- `GET  catalog` -> catálogo do gateway (+ `risk_notice_version`).
- `POST /` `{provider, consent:true, login_flow?}` -> `{connection, step}`.
- `POST :id/step` `{step_id, kind, data}` -> `{connection, step}`.
- `GET  :id` -> `{connection, step?}` (poll para espera/QR).
- `POST :id/cancel`, `POST :id/disconnect`, `POST :id/revoke`, `POST :id/reauth` -> `{connection, step?}`.
- `POST :id/finalize` `{name, team_id?, agent_bot_id?, sync_since_days}` -> `{inbox}`; cria `Channel::<Provider>Unofficial` + inbox, grava `connection_id`, registra `PUT /delivery` no gateway com webhook assinado.
- Webhook de entrada (gateway -> Rails, sem sessão de usuário): `POST /webhooks/channels/:channel_type/:id` (`instagram_unofficial|messenger_unofficial|whatsapp_unofficial|tiktok_unofficial`), assinatura HMAC conforme acima.
Canal Chatwoot: `Channel::InstagramUnofficial`, `Channel::MessengerUnofficial` (renomeia o antigo `FacebookUnofficial`; manter o antigo como legado `reauth_required` – CH-9), `Channel::WhatsappUnofficial`, `Channel::TiktokUnofficial`. Colunas novas: `connection_id uuid`, `state string`, `webhook_secret` (cifrado), `last_error_code`, `last_activity_at`, `connector_version`; saem `cookies`/polling do caminho novo (colunas antigas ficam sem uso, nunca apagar).
