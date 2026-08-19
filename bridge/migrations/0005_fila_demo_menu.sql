-- Produto-08: fila de demonstração sem IA (menu numerado "digite 1, digite 2").
--
-- `menu_step` fica em `conversation_states` (mesma tabela do fluxo IA/Humano,
-- linha separada por tenant_id + chatwoot_conversation_id — nunca a mesma
-- linha que o fluxo de IA usa, porque a inbox da demo nunca aciona
-- `ai_config_for`/`_handle_message`; ver app/api/agent_bot.py). O campo
-- `state` desta tabela continua no default 'ai_active' para essas linhas e é
-- simplesmente ignorado pelo menu bot — nenhuma leitura cruza os dois campos.
ALTER TABLE conversation_states
    ADD COLUMN IF NOT EXISTS menu_step TEXT NOT NULL DEFAULT '';

-- Config por tenant+inbox da fila demo: quais Teams reais recebem cada opção
-- do menu (podem nem ter humano de verdade — é demonstração). Tabela própria,
-- não reaproveita tenant_ai_config: aquela tabela é o gatilho que liga o
-- kernel (`ai_config_for`), e a inbox da demo nunca pode aparecer lá.
CREATE TABLE IF NOT EXISTS menu_bot_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant_links (tenant_id) ON DELETE CASCADE,
    chatwoot_inbox_id BIGINT NOT NULL,
    team_vendas_id BIGINT,
    team_suporte_id BIGINT,
    team_financeiro_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, chatwoot_inbox_id)
);
