-- 0004: token opaco para o Webhook de CONTA que carrega conversation_updated
-- (mudança de label), usado pelo botão "Devolver para IA" (macro + label
-- reservada `ia-retomar`).
--
-- Esse webhook é um mecanismo SEPARADO do Agent Bot webhook que já existe
-- (Settings -> Integrations -> Webhooks, `Api::V1::Accounts::WebhooksController`,
-- não `Api::V1::Accounts::AgentBotsController`). O payload dele
-- (`Conversations::EventDataPresenter#push_data`) não inclui account_id nem
-- o id global da conversa — só `id` (que é o display_id, sequencial por
-- conta, colide entre tenants diferentes) e `labels`/`meta.team`. Sem
-- account_id no corpo, não dá pra resolver o tenant olhando o payload.
--
-- Solução: mesmo padrão do webhook do WhatsApp não-oficial
-- (tenant_channels.webhook_token) — um token opaco por tenant embutido na
-- própria URL do webhook de conta, resolvido ANTES de olhar o corpo.

ALTER TABLE tenant_links
    ADD COLUMN IF NOT EXISTS conversation_webhook_token TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS tenant_links_conversation_webhook_token_idx
    ON tenant_links (conversation_webhook_token)
    WHERE conversation_webhook_token IS NOT NULL;
