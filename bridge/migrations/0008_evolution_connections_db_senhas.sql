-- Produto-09 (mega-spec-reestrutura) -- achado real 24/08/2026: senha do
-- Postgres/Redis internos do container Evolution era gerada de novo em toda
-- chamada de `provisionar_container`, mesmo quando os containers dependentes
-- já existiam (sobreviventes de uma tentativa anterior interrompida) --
-- descasamento permanente de senha, container em crash-loop pra sempre.
-- Persistir aqui e ler de volta em vez de gerar sempre resolve de vez.

ALTER TABLE evolution_connections ADD COLUMN pg_password_encrypted TEXT;
ALTER TABLE evolution_connections ADD COLUMN redis_password_encrypted TEXT;
