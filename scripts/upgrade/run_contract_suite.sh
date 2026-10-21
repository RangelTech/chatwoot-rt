#!/usr/bin/env bash
# Roda a suite de contrato do fork (UPG-3) dentro de chatwoot/. Uso: bash scripts/upgrade/run_contract_suite.sh
# Requer banco/Redis de teste configurados (mesmas variaveis do CI). Em maquina sem Ruby, ver docs/runbooks/upgrade-mensal.md.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)/chatwoot"
SPECS="$(grep -v '^#' spec/fork_contract/CONTRACT_SPECS.txt | grep -v '^$' | tr '\n' ' ')"
# shellcheck disable=SC2086
RAILS_ENV=test bundle exec rspec $SPECS
