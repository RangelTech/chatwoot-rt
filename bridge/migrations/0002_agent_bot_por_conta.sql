-- 0002: o Agent Bot da conta, para a IA atender caixa que a ponte não criou.
--
-- Até aqui o bot só era associado à inbox no momento em que a PONTE criava o
-- canal (W-API). Mas o desenho da instalação é outro: o cliente conecta o
-- Instagram, o Messenger ou o WhatsApp oficial DENTRO do Chatwoot, e essa inbox
-- nasce sem bot nenhum. O cliente então escolhia o agente na nossa tela e nada
-- respondia — sem erro, sem log, porque o Chatwoot simplesmente nunca chamava a
-- ponte.
--
-- Guardar o id evita recriar um bot por vinculação: um por conta basta, e o
-- Chatwoot não deduplica por nome.

ALTER TABLE tenant_links
    ADD COLUMN IF NOT EXISTS chatwoot_agent_bot_id BIGINT;
