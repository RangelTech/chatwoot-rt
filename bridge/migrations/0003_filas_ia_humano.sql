-- 0003: Team "Fila IA" por tenant, para toda conversa em ai_active cair numa
-- fila própria dentro do Chatwoot.
--
-- Já existia `handoff_team_id` (o time de HUMANO, usado no handoff da IA),
-- mas nenhuma conversa em ai_active era atribuída a Team nenhum. Quem abria o
-- Chatwoot só enxergava "o que foi escalado" — não tinha como filtrar "o que
-- a IA está atendendo agora". `ai_team_id` é o campo novo, preenchido no
-- provisionamento (junto com handoff_team_id, na config padrão do tenant).

ALTER TABLE tenant_ai_config
    ADD COLUMN IF NOT EXISTS ai_team_id BIGINT;
