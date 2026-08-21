-- A implementação WAPI mediada pela ponte (`app/providers/wapi.py`,
-- `/webhooks/wapi/:token`, `/outbound/:token`, `/admin/channels`) foi
-- removida — só tinha dado de fixture de teste (16 linhas em
-- tenant_channels, nenhum cliente real; confirmado 21/08/2026). O canal
-- WAPI de verdade agora é nativo no Chatwoot (`Channel::Wapi`, produto-05
-- seção 3), fala direto com o provedor, não passa mais pela ponte.
DROP TABLE IF EXISTS channel_events;
DROP TABLE IF EXISTS tenant_channels;
