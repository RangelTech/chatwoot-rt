#!/usr/bin/env python3
"""Mede a divergencia do fork em relacao ao upstream importado.

Uso: python scripts/upgrade/divergence.py [--base upstream-import] [--head HEAD] [--json] [--fail-on-unmarked]

Compara a arvore chatwoot/ entre a branch `upstream-import` (codigo upstream exato) e o fork,
agrupa por familia e lista os arquivos do nucleo (modificados) que NAO estao no contrato
`chatwoot/fork_extensions.yml` (sem marcador = ponto de contato nao rastreado).
"""
import argparse
import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

FAMILIES = [
    ("traducoes", re.compile(r"^(app/javascript/.*/i18n/locale/|config/locales/)")),
    ("marca_assets", re.compile(r"^(public/|branding/|app/javascript/dashboard/assets/|app/javascript/.*\.svg$|app/assets/)")),
    ("testes", re.compile(r"^spec/")),
    ("migracoes_schema", re.compile(r"^db/")),
    ("rt_ai_unificacao", re.compile(r"(/rt_ai/|/rt/|/ragent/|ai_roles|rt_ai|ragent|kanban)", re.I)),
    ("canais_wapi_evolution", re.compile(r"(wapi|evolution)", re.I)),
    ("infra_entrypoints", re.compile(r"^(Dockerfile|entrypoints/|docker|\.github/|\.env)")),
]


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def family(path):
    for name, rx in FAMILIES:
        if rx.search(path):
            return name
    return "nucleo_upstream"


def load_manifest():
    try:
        import yaml  # type: ignore
    except ImportError:
        out = subprocess.run(
            ["ruby", "-ryaml", "-rjson", "-e", "puts JSON.generate(YAML.safe_load(File.read('chatwoot/fork_extensions.yml')))"],
            cwd=ROOT, capture_output=True, text=True,
        )
        return json.loads(out.stdout)
    return yaml.safe_load((ROOT / "chatwoot/fork_extensions.yml").read_text(encoding="utf-8"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="upstream-import")
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--fail-on-unmarked", action="store_true")
    a = ap.parse_args()

    rows = []
    for line in git("diff", "--no-renames", "--name-status", a.base, a.head, "--", "chatwoot").splitlines():
        status, path = line.split("\t", 1)
        rows.append((status, path[len("chatwoot/"):]))

    manifest = load_manifest()
    tracked = set()
    for ext in manifest.get("extensions", []):
        tracked.update(ext.get("touchpoints") or [])
        tracked.update((ext.get("markers") or {}).keys())

    por_familia = defaultdict(Counter)
    for status, path in rows:
        por_familia[family(path)][status] += 1

    nucleo_mod = sorted(p for s, p in rows if s == "M" and family(p) == "nucleo_upstream")
    sem_marcador = [p for p in nucleo_mod if p not in tracked]
    enterprise_tocado = sorted(p for _, p in rows if p.startswith("enterprise/"))

    result = {
        "base": a.base,
        "total": len(rows),
        "por_familia": {k: dict(v) for k, v in sorted(por_familia.items())},
        "nucleo_modificado": nucleo_mod,
        "nucleo_modificado_sem_marcador": sem_marcador,
        "enterprise_tocado": enterprise_tocado,
    }
    if a.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(f"# Divergencia {a.base} -> {a.head}: {len(rows)} arquivos\n")
        print("| familia | adicionados | modificados | removidos |\n|---|---|---|---|")
        for k, v in sorted(por_familia.items()):
            print(f"| {k} | {v['A']} | {v['M']} | {v['D']} |")
        print(f"\nNucleo modificado: {len(nucleo_mod)} arquivos; sem marcador no contrato: {len(sem_marcador)}")
        for p in sem_marcador:
            print(f"- {p}")
        print(f"\nenterprise/ tocado: {len(enterprise_tocado)}")
        for p in enterprise_tocado:
            print(f"- {p}")
    if a.fail_on_unmarked and sem_marcador:
        sys.exit(1)


if __name__ == "__main__":
    main()
