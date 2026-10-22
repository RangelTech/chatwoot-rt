#!/usr/bin/env bash
# Ensaio das migracoes do upgrade numa COPIA do banco, em contêineres descartaveis (UPG-6, passos 6 e 7).
# Nunca toca em producao: recebe um dump (pg_dump -Fc) e sobe um PG/Redis proprios, que somem no fim.
#
# Uso: DUMP=/caminho/dump.fc CW_IMAGE=chatwoot:development scripts/upgrade/rehearse_migrations.sh [pasta_chatwoot]
#   pasta_chatwoot : codigo da versao nova (padrao ./chatwoot)
# Saida: tempo da restauracao, tempo das migracoes, migracoes aplicadas, lista de pendentes depois (deve ser 0)
# e `rt:brand:verify`. Codigo de saida != 0 se algo falhar.
set -euo pipefail

SRC="$(cd "${1:-chatwoot}" && pwd -W 2>/dev/null || (cd "${1:-chatwoot}" && pwd))"
DUMP="${DUMP:?informe DUMP=<arquivo pg_dump -Fc>}"
IMAGE="${CW_IMAGE:-chatwoot:development}"
TAG="rehearsal-$$"
NET="net-$TAG"
PG="pg-$TAG"
RD="rd-$TAG"

cleanup() { docker rm -f "$PG" "$RD" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker network create "$NET" >/dev/null
docker run -d --name "$PG" --network "$NET" -e POSTGRES_PASSWORD=postgres pgvector/pgvector:pg16 >/dev/null
docker run -d --name "$RD" --network "$NET" redis:7-alpine >/dev/null
until docker exec "$PG" pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done

echo "== restaurando a copia"
t0=$(date +%s)
docker exec "$PG" createdb -U postgres chatwoot_rehearsal
docker cp "$DUMP" "$PG:/tmp/dump.fc"
docker exec "$PG" pg_restore -U postgres -d chatwoot_rehearsal --no-owner --no-privileges /tmp/dump.fc || true
t1=$(date +%s)
echo "restauracao: $((t1 - t0))s"

run_rails() {
  MSYS_NO_PATHCONV=1 docker run --rm --network "$NET" -e RAILS_ENV=production -e SECRET_KEY_BASE=rehearsal \
    -e POSTGRES_HOST="$PG" -e POSTGRES_USERNAME=postgres -e POSTGRES_PASSWORD=postgres \
    -e POSTGRES_DATABASE=chatwoot_rehearsal -e REDIS_URL="redis://$RD:6379" -e RT_UI_CONTEXT_SECRET=rehearsal \
    -e FRONTEND_URL=http://localhost -e DISABLE_TELEMETRY=true \
    -v "$SRC:/app" -w /app "$IMAGE" sh -c "$1"
}

before="$(docker exec "$PG" psql -U postgres -d chatwoot_rehearsal -Atc 'select count(*) from schema_migrations')"
echo "== migracoes (antes: $before aplicadas)"
t2=$(date +%s)
run_rails "bundle exec rails db:migrate 2>&1 | tail -40"
t3=$(date +%s)
after="$(docker exec "$PG" psql -U postgres -d chatwoot_rehearsal -Atc 'select count(*) from schema_migrations')"
echo "migracoes: $((t3 - t2))s; aplicadas agora: $((after - before)); total: $after"

echo "== pendentes e marca"
run_rails "bundle exec rails runner 'puts \"pendentes=#{ActiveRecord::Base.connection.migration_context.needs_migration? ? 1 : 0}\"; puts \"versao=#{Chatwoot.config[:version]}\"' 2>&1 | tail -3"
run_rails "bundle exec rails rt:brand:verify 2>&1 | tail -5" || true
echo "ensaio concluido (contêineres descartados no fim)"
