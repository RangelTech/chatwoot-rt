-- Fase F (F-6/F-7): a ponte deixa de guardar o estado da conversa (agora derivado do Chatwoot) e mantem so
-- (a) mensagens ja processadas (deduplicacao) e (b) conversa+agente -> sessao do kernel.
CREATE TABLE IF NOT EXISTS processed_messages (
    tenant_id UUID NOT NULL REFERENCES tenant_links (tenant_id) ON DELETE CASCADE,
    chatwoot_message_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, chatwoot_message_id)
);

CREATE TABLE IF NOT EXISTS conversation_agent_sessions (
    tenant_id UUID NOT NULL REFERENCES tenant_links (tenant_id) ON DELETE CASCADE,
    chatwoot_conversation_id BIGINT NOT NULL,
    agent_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    -- ultima mensagem do Chatwoot que este agente ja viu (o contexto enviado e o que veio depois).
    last_message_id BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, chatwoot_conversation_id, agent_id)
);
