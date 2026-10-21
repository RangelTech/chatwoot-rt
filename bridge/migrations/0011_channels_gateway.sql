-- Fase CH: gateway de canais nao oficiais. Nenhuma coluna guarda senha, cookie
-- ou token de sessao: a sessao mora so no bridge (mautrix) ou no worker.
CREATE TABLE IF NOT EXISTS rt_channel_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id BIGINT NOT NULL,
    provider TEXT NOT NULL CHECK (provider IN ('instagram', 'messenger', 'whatsapp', 'tiktok')),
    mode TEXT NOT NULL DEFAULT 'experimental' CHECK (mode IN ('experimental')),
    state TEXT NOT NULL DEFAULT 'pending_auth' CHECK (state IN (
        'pending_auth', 'awaiting_2fa', 'awaiting_challenge', 'connected', 'degraded',
        'reauth_required', 'disconnected', 'revoked')),
    matrix_user TEXT,
    gateway_login_id TEXT,
    login_process_id TEXT,
    login_flow TEXT,
    external_label TEXT NOT NULL DEFAULT '',
    connector_version TEXT NOT NULL DEFAULT '',
    last_activity_at TIMESTAMPTZ,
    last_error_code TEXT NOT NULL DEFAULT '',
    sync_status TEXT NOT NULL DEFAULT 'idle',
    sync_progress INTEGER NOT NULL DEFAULT 0,
    sync_since_days INTEGER NOT NULL DEFAULT 60,
    webhook_url TEXT,
    webhook_secret_encrypted TEXT,
    inbox_ref TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS rt_channel_connections_account_idx
    ON rt_channel_connections (account_id, provider);
CREATE UNIQUE INDEX IF NOT EXISTS rt_channel_connections_matrix_user_uq
    ON rt_channel_connections (matrix_user) WHERE matrix_user IS NOT NULL;

CREATE TABLE IF NOT EXISTS rt_channel_rooms (
    room_id TEXT PRIMARY KEY,
    connection_id UUID NOT NULL REFERENCES rt_channel_connections (id),
    account_id BIGINT NOT NULL,
    conversation_external_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS rt_channel_rooms_conn_idx ON rt_channel_rooms (connection_id);

-- Idempotencia de entrada: tenant + conexao + id externo.
CREATE TABLE IF NOT EXISTS rt_channel_messages (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL,
    connection_id UUID NOT NULL REFERENCES rt_channel_connections (id),
    external_id TEXT NOT NULL,
    direction TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (account_id, connection_id, external_id)
);

-- Fila de saida (envios) e de webhooks para o Rails, com retentativa e dead-letter.
CREATE TABLE IF NOT EXISTS rt_channel_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES rt_channel_connections (id),
    account_id BIGINT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('send', 'webhook')),
    idempotency_key TEXT NOT NULL,
    payload JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sent', 'failed', 'dead')),
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    external_id TEXT,
    last_error TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (connection_id, kind, idempotency_key)
);
CREATE INDEX IF NOT EXISTS rt_channel_outbox_due_idx
    ON rt_channel_outbox (status, next_attempt_at);

CREATE TABLE IF NOT EXISTS rt_channel_audit (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL,
    connection_id UUID,
    actor_id TEXT NOT NULL DEFAULT '',
    action TEXT NOT NULL,
    detail JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS rt_channel_audit_conn_idx ON rt_channel_audit (connection_id, created_at);

-- Limite de tentativas de login: so hash do identificador (nunca o usuario em claro).
CREATE TABLE IF NOT EXISTS rt_channel_login_attempts (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL,
    provider TEXT NOT NULL,
    identifier_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS rt_channel_login_attempts_idx
    ON rt_channel_login_attempts (account_id, provider, identifier_hash, created_at);

-- Replay do webhook do Matrix (transacoes do appservice).
CREATE TABLE IF NOT EXISTS rt_channel_appservice_txns (
    txn_id TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
