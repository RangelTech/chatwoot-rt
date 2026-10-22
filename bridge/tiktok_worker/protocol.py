"""Protocolo manager <-> worker: JSON-lines (uma linha JSON por mensagem) em stdin/stdout.

Sem dependências fora da biblioteca padrão (a imagem do worker é separada da bridge).

Manager -> worker (comando):  {"id": <int>, "cmd": "<nome>", "args": {...}}
Worker  -> manager (resposta): {"id": <int>, "ok": true, "result": {...}}
                               {"id": <int>, "ok": false, "error_code": "...", "detail": "..."}
Worker  -> manager (evento):   {"event": "<nome>", ...}

Comandos: login_start, login_poll, login_code, login_cancel, connect, send, sync, health,
logout, drain (finaliza entregas pendentes e sai).
Eventos: ready, message, session_invalid, degraded, recovered.

Segredos (código 2FA) trafegam só em `args` por stdin; nunca em argv, env ou log.
"""

from __future__ import annotations

import json
from typing import Any

MAX_LINE = 1_000_000

COMMANDS = frozenset(
    {
        "login_start",
        "login_poll",
        "login_code",
        "login_cancel",
        "connect",
        "send",
        "sync",
        "health",
        "logout",
        "drain",
        "fake",  # controle de testes; só aceito pelo driver fake
    }
)
SECRET_ARGS = frozenset({"code"})


def encode(obj: dict[str, Any]) -> bytes:
    return (json.dumps(obj, separators=(",", ":"), ensure_ascii=False) + "\n").encode()


def decode(line: bytes | str) -> dict[str, Any]:
    if isinstance(line, bytes):
        line = line.decode("utf-8", errors="replace")
    obj = json.loads(line)
    if not isinstance(obj, dict):
        raise ValueError("linha não é objeto")
    return obj


def redact(obj: dict[str, Any]) -> dict[str, Any]:
    """Cópia segura para log: remove valores de argumentos secretos."""
    out = dict(obj)
    args = out.get("args")
    if isinstance(args, dict):
        out["args"] = {k: ("***" if k in SECRET_ARGS else v) for k, v in args.items()}
    return out
