-- pgcrypto fornece gen_random_bytes/gen_random_uuid usados abaixo.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Estado operacional da ponte.
--
-- A ponte não duplica o que o Chatwoot ou o agent-platform já sabem: ela
-- guarda só o que liga os dois mundos (mapeamentos), o que garante entrega
-- exatamente uma vez (idempotência) e o que precisa sobreviver a um replay.

CREATE TABLE IF NOT EXISTS tenant_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Tenant no agent-platform: a âncora de todo isolamento desta camada.
    tenant_id UUID NOT NULL UNIQUE,
    tenant_key TEXT NOT NULL,
    tenant_name TEXT NOT NULL DEFAULT '',
    chatwoot_account_id BIGINT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Paridade de usuários: quem existe na plataforma ganha um usuário
-- equivalente no Chatwoot, para o SSO não pedir cadastro novo.
CREATE TABLE IF NOT EXISTS user_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant_links (tenant_id) ON DELETE CASCADE,
    platform_user_id UUID NOT NULL,
    email TEXT NOT NULL,
    chatwoot_user_id BIGINT,
    role TEXT NOT NULL DEFAULT 'agent',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, platform_user_id)
);

-- Canal por tenant (W-API hoje; outro provedor amanhã). O token fica cifrado.
CREATE TABLE IF NOT EXISTS tenant_channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant_links (tenant_id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'wapi',
    -- Identificador do canal no provedor (instância da W-API, por exemplo).
    external_id TEXT NOT NULL,
    credentials_encrypted TEXT,
    api_base TEXT NOT NULL DEFAULT 'https://api.w-api.app/v1',
    -- Inbox do tipo API criada no Chatwoot para receber as mensagens.
    chatwoot_inbox_id BIGINT,
    chatwoot_inbox_identifier TEXT,
    -- Sufixo opaco da URL de webhook deste canal.
    webhook_token TEXT NOT NULL DEFAULT encode(gen_random_bytes(18), 'hex'),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, external_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS tenant_channels_webhook_token_idx
    ON tenant_channels (webhook_token);

-- Qual template do agent-platform atende cada tenant/inbox, e quando a IA
-- deve sair de cena.
CREATE TABLE IF NOT EXISTS tenant_ai_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant_links (tenant_id) ON DELETE CASCADE,
    chatwoot_inbox_id BIGINT,
    template_id UUID,
    -- Chave de integração da API pública do agent-platform (cifrada).
    integration_key_encrypted TEXT,
    autopilot BOOLEAN NOT NULL DEFAULT TRUE,
    handoff_team_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, chatwoot_inbox_id)
);

-- Todo evento que entra é gravado cru ANTES do parsing e deduplicado por
-- chave do provedor: provedor reenvia, Cloud Run reprocessa, e a conversa
-- não pode duplicar por isso.
CREATE TABLE IF NOT EXISTS channel_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID,
    channel_id UUID REFERENCES tenant_channels (id) ON DELETE SET NULL,
    provider TEXT NOT NULL DEFAULT 'wapi',
    -- Chave natural do evento no provedor (id da mensagem).
    dedup_key TEXT,
    direction TEXT NOT NULL DEFAULT 'in',
    raw_body TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'received',
    detail TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS channel_events_dedup_idx
    ON channel_events (provider, dedup_key) WHERE dedup_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS channel_events_tenant_idx
    ON channel_events (tenant_id, created_at DESC);

-- Estado da conversa do ponto de vista da ponte: quem está no comando, a IA
-- ou um humano. Sem isso os dois respondem ao mesmo tempo.
CREATE TABLE IF NOT EXISTS conversation_states (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant_links (tenant_id) ON DELETE CASCADE,
    chatwoot_conversation_id BIGINT NOT NULL,
    state TEXT NOT NULL DEFAULT 'ai_active',
    contact_identifier TEXT NOT NULL DEFAULT '',
    -- thread_id usado no kernel, para a conversa não perder memória.
    session_id TEXT NOT NULL DEFAULT '',
    last_error TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, chatwoot_conversation_id)
);
