#!/bin/sh
# Serviço web do Chatwoot no Cloud Run.
#
# As migrações NÃO rodam aqui: com várias instâncias subindo em paralelo, duas
# tentariam migrar o mesmo banco ao mesmo tempo. Migração é passo explícito de
# deploy (ver infra/deploy.sh migrate).
set -eu

: "${PORT:=3000}"
exec bundle exec rails server -b 0.0.0.0 -p "${PORT}" -e production
