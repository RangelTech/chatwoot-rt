#!/usr/bin/env bash
# Mescla uma versao do upstream (ja importada em `upstream-import`) numa branch de trabalho e resolve
# automaticamente o que tem regra (UPG-4). Nao empurra nada e nao toca em producao.
#
# Uso: scripts/upgrade/merge_upstream.sh <versao> [--branch upgrade/<versao>] [--dry-run]
#   --dry-run : mescla, mede (conflitos/arquivos), escreve o resumo JSON e ABORTA a mesclagem
#               (e o que o ensaio semanal usa, UPG-5).
# Saida: resumo em JSON no stdout (ultima linha) com target, status, conflicts, files.
#
# Regras de conflito:
#   - i18n *.json (en, pt_BR, survey, widget): mescla por chave (scripts/upgrade/merge_i18n.py);
#   - config/locales/*.yml e enterprise/**: aceita o upstream (a marca volta pelo contrato/rt:brand);
#   - qualquer outro: fica como conflito e entra na contagem (resolver pelos marcadores do contrato).
set -euo pipefail

VERSION="${1:?uso: merge_upstream.sh <versao> [--branch X] [--dry-run]}"
shift || true
BRANCH="upgrade/${VERSION}"
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
HERE="$ROOT/scripts/upgrade"
PY="${PYTHON:-python3}"
"$PY" -c "import sys" >/dev/null 2>&1 || PY=python

git rev-parse --verify -q upstream-import >/dev/null || { echo "branch upstream-import ausente (rode import_upstream.sh)" >&2; exit 3; }
git log -1 --format=%s upstream-import | grep -q "Chatwoot ${VERSION}\$" || { echo "upstream-import nao esta em ${VERSION}" >&2; exit 3; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "arvore de trabalho suja" >&2; exit 3; }

START_REF="$(git rev-parse HEAD)"
if [ "$DRY" = "0" ]; then git switch -c "$BRANCH"; fi

set +e
git merge --no-commit --no-ff upstream-import >/dev/null 2>&1
set -e

BASE_JSON_TMP="$(mktemp -d)"
trap 'rm -rf "$BASE_JSON_TMP"' EXIT
MERGE_BASE="$(git merge-base "$START_REF" upstream-import)"

auto=0
for f in $(git diff --name-only --diff-filter=U); do
  case "$f" in
    chatwoot/app/javascript/*/i18n/locale/*.json|chatwoot/app/javascript/*/i18n/locale/*/*.json)
      git show "${MERGE_BASE}:${f}" > "$BASE_JSON_TMP/base.json" 2>/dev/null || echo '{}' > "$BASE_JSON_TMP/base.json"
      git show "${START_REF}:${f}" > "$BASE_JSON_TMP/fork.json" 2>/dev/null || echo '{}' > "$BASE_JSON_TMP/fork.json"
      git show "upstream-import:${f}" > "$BASE_JSON_TMP/theirs.json" 2>/dev/null || echo '{}' > "$BASE_JSON_TMP/theirs.json"
      "$PY" "$HERE/merge_i18n.py" "$BASE_JSON_TMP/base.json" "$BASE_JSON_TMP/fork.json" "$BASE_JSON_TMP/theirs.json" > "$f"
      git add "$f"; auto=$((auto+1)) ;;
    chatwoot/config/locales/*.yml|chatwoot/enterprise/*)
      git checkout --theirs -- "$f" 2>/dev/null && git add "$f" || git rm -q --cached "$f" 2>/dev/null || true
      auto=$((auto+1)) ;;
  esac
done

CONFLICTS="$(git diff --name-only --diff-filter=U | wc -l | tr -d ' ')"
FILES="$(git diff --name-only --cached | wc -l | tr -d ' ')"
UNRESOLVED="$(git diff --name-only --diff-filter=U | sed 's/^/  - /')"
STATUS=clean; [ "$CONFLICTS" = "0" ] || STATUS=conflicts

echo "auto-resolvidos: ${auto}; conflitos restantes: ${CONFLICTS}; arquivos alterados: ${FILES}" >&2
[ -z "$UNRESOLVED" ] || { echo "conflitos manuais:" >&2; echo "$UNRESOLVED" >&2; }

if [ "$DRY" = "1" ]; then git merge --abort >/dev/null 2>&1 || git reset --hard "$START_REF" >/dev/null; fi
printf '{"target":"%s","status":"%s","conflicts":%s,"files":%s,"auto_resolved":%s}\n' "$VERSION" "$STATUS" "$CONFLICTS" "$FILES" "$auto"
