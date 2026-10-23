#!/bin/sh
# HEALTHCHECK da imagem chatwoot-rails (mesma imagem roda web, worker e migrate).
#  - Worker Sidekiq (sem HTTP): saudavel se o processo sidekiq esta vivo.
#  - Web: GET /health em 127.0.0.1:$PORT (default 3000) precisa dar 2xx.
# Detecta o modo pelo processo, entao nao exige env nem flag por servico.
if pgrep -f sidekiq >/dev/null 2>&1; then
  exit 0
fi
exec wget -q -T 5 -O /dev/null "http://127.0.0.1:${PORT:-3000}/health"
