-- Canal externo não tem stream: por caixa, o motor decide se a ponte manda UMA mensagem curta de
-- progresso antes da resposta final. Padrão desligado (entrega só a resposta final).
ALTER TABLE tenant_ai_config
    ADD COLUMN IF NOT EXISTS show_progress BOOLEAN NOT NULL DEFAULT FALSE;
