#!/usr/bin/env python3
"""Mescla de traducoes por CHAVE (UPG-4): resolve conflitos de arquivos *.json de locale sem mao.

Uso: merge_i18n.py <base.json> <fork.json> <upstream_novo.json> > saida.json

Regras, folha a folha:
  - fork igual a base            -> upstream novo (acompanha o upstream);
  - fork mudou, upstream nao     -> mantem o fork (nossas chaves e nossa marca);
  - os dois mudaram a mesma chave-> upstream novo + marca reaplicada;
  - chave nova no upstream       -> entra, com a marca reaplicada;
  - chave removida no upstream   -> sai, exceto se for do fork (nao existia na base).
A marca (Chatwoot -> LUAR) e reaplicada a todo texto que vem do upstream, respeitando as mesmas
excecoes tecnicas de `rt:brand:verify`. Idempotente.
"""
import json
import re
import sys

ALLOWED = [
    r"window\.chatwoot\w*", r"chatwoot\.help", r"www\.chatwoot\.com/(?:terms|privacy-policy)",
    r"Unique identifier for Chatwoot as the Service Provider", r"Identificador exclusivo do Chatwoot",
    r"UPDATE_CHATWOOT", r"latestChatwootVersion",
]
# Textos do produto que o fork reescreve (nao e so troca de nome).
OVERRIDES = {
    "Captain AI": "IA",
}

_MISSING = object()


def rebrand(text):
    if not isinstance(text, str) or "hatwoot" not in text:
        return text
    protected = {}

    def keep(match):
        key = f"\u0000{len(protected)}\u0000"
        protected[key] = match.group(0)
        return key

    for pattern in ALLOWED:
        text = re.sub(pattern, keep, text)
    text = text.replace("Chatwoot", "LUAR")
    for key, original in protected.items():
        text = text.replace(key, original)
    return text


def rebrand_tree(node):
    if isinstance(node, dict):
        return {k: rebrand_tree(v) for k, v in node.items()}
    if isinstance(node, list):
        return [rebrand_tree(v) for v in node]
    return rebrand(node)


def merge(base, fork, theirs):
    if isinstance(theirs, dict) and isinstance(fork, dict) and isinstance(base, (dict, type(_MISSING))):
        base_d = base if isinstance(base, dict) else {}
        out = {}
        for key, tval in theirs.items():
            out[key] = merge(base_d.get(key, _MISSING), fork.get(key, _MISSING), tval)
        for key, fval in fork.items():
            if key not in theirs and key not in base_d:
                out[key] = fval  # chave so do fork (ex.: ragent, kanban)
        return out
    if fork is _MISSING:
        return rebrand_tree(theirs)
    if base is _MISSING:
        return fork if theirs is _MISSING else rebrand_tree(theirs)
    if fork == base:
        return rebrand_tree(theirs)
    if theirs == base:
        return fork
    return rebrand_tree(theirs)


def main():
    base_p, fork_p, theirs_p = sys.argv[1:4]
    load = lambda p: json.load(open(p, encoding="utf-8")) if p != "-" else {}
    merged = merge(load(base_p), load(fork_p), load(theirs_p))
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    sys.stdout.write(json.dumps(merged, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
