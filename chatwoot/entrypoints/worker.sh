#!/usr/bin/env bash
# Worker Sidekiq: e-mails, automações, jobs de conversa.
#
# Roda com min-instances=1 porque fila parada é atendimento parado — sem o
# worker, mensagens ficam presas sem ninguém perceber.
set -euo pipefail

exec bundle exec sidekiq -C config/sidekiq.yml
