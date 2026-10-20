#!/usr/bin/env bash
# Importa uma versao exata do Chatwoot (tag oficial) como NOVO commit na branch `upstream-import`,
# com o codigo em chatwoot/ (mesmo layout do fork). Historico sintetico: 1 commit por versao.
# Primeira vez (sem a branch): cria orfa. Depois: acrescenta.
#
# Uso: scripts/upgrade/import_upstream.sh <versao>      ex.: 4.17.0
# Nao altera a branch atual nem a arvore de trabalho (usa um worktree temporario).
set -euo pipefail

VERSION="${1:?uso: import_upstream.sh <versao>}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "versao invalida (so estavel X.Y.Z): $VERSION" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
WORK="$(mktemp -d)"
trap 'git worktree remove --force "$WORK/wt" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

git -c core.autocrlf=false clone -q --depth 1 --branch "v${VERSION}" https://github.com/chatwoot/chatwoot "$WORK/src"
[ "$(cat "$WORK/src/VERSION_CW")" = "$VERSION" ] || { echo "VERSION_CW do upstream difere de $VERSION" >&2; exit 3; }

if git rev-parse --verify -q upstream-import >/dev/null; then
  git worktree add -q --detach "$WORK/wt" upstream-import
else
  git worktree add -q --orphan -b upstream-import "$WORK/wt"
fi

(
  cd "$WORK/wt"
  rm -rf chatwoot && mkdir chatwoot
  (cd "$WORK/src" && tar --exclude=.git -cf - .) | tar -xf - -C chatwoot
  git add -A >/dev/null 2>&1
  git -c core.autocrlf=false commit -q -m "import(upstream): Chatwoot ${VERSION}"
  NEW="$(git rev-parse HEAD)"
  echo "$NEW" > "$WORK/new_sha"
)
NEW="$(cat "$WORK/new_sha")"
git worktree remove --force "$WORK/wt"
git branch -f upstream-import "$NEW"
echo "upstream-import -> $NEW (Chatwoot ${VERSION})"
