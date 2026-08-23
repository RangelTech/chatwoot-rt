-- Produto-05 seção 4 (QR automático): estado do provisionamento privilegiado
-- de instâncias Evolution por tenant. O administrador do tenant nunca vê
-- nem digita instance_name/api_url/api_key -- ficam só aqui, cifrados, e são
-- resolvidos pela ponte a partir da conta do Chatwoot já autenticada.
CREATE TABLE IF NOT EXISTS evolution_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant_links (tenant_id) ON DELETE CASCADE,
    indice INTEGER NOT NULL DEFAULT 1,
    instance_name TEXT NOT NULL,
    api_url TEXT NOT NULL,
    api_key_encrypted TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'provisioning'
        CHECK (status IN ('provisioning', 'ready', 'failed')),
    last_error TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, indice)
);
