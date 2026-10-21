"""Persistencia do gateway (tabelas rt_channel_*). Nenhuma coluna guarda credencial."""

from __future__ import annotations

import json
from typing import Any

from psycopg.types.json import Jsonb

from app.db import get_connection

_CONN_COLS = (
    "id::text AS id, account_id, provider, mode, state, matrix_user, gateway_login_id, "
    "login_process_id, login_flow, external_label, connector_version, last_activity_at, "
    "last_error_code, sync_status, sync_progress, sync_since_days, webhook_url, inbox_ref, "
    "(webhook_secret_encrypted IS NOT NULL) AS has_delivery, created_at, updated_at"
)


def create_connection(*, account_id: int, provider: str, login_flow: str | None) -> dict:
    with get_connection() as conn:
        return conn.execute(
            "INSERT INTO rt_channel_connections (account_id, provider, login_flow) "
            f"VALUES (%s, %s, %s) RETURNING {_CONN_COLS}",
            (account_id, provider, login_flow),
        ).fetchone()


def set_matrix_user(connection_id: str, matrix_user: str) -> None:
    with get_connection() as conn:
        conn.execute(
            "UPDATE rt_channel_connections SET matrix_user=%s, updated_at=now() WHERE id::text=%s",
            (matrix_user, connection_id),
        )


def get_connection_row(connection_id: str, account_id: int | None = None) -> dict | None:
    """Com `account_id`, conexao de outro tenant e tratada como inexistente."""
    sql = f"SELECT {_CONN_COLS} FROM rt_channel_connections WHERE id::text=%s"
    args: list[Any] = [connection_id]
    if account_id is not None:
        sql += " AND account_id=%s"
        args.append(account_id)
    with get_connection() as conn:
        return conn.execute(sql, args).fetchone()


def list_connections(account_id: int) -> list[dict]:
    with get_connection() as conn:
        return conn.execute(
            f"SELECT {_CONN_COLS} FROM rt_channel_connections WHERE account_id=%s "
            "ORDER BY created_at",
            (account_id,),
        ).fetchall()


_UPDATABLE = {
    "state",
    "gateway_login_id",
    "login_process_id",
    "login_flow",
    "external_label",
    "connector_version",
    "last_activity_at",
    "last_error_code",
    "sync_status",
    "sync_progress",
    "sync_since_days",
    "webhook_url",
    "webhook_secret_encrypted",
    "inbox_ref",
}


def update_connection(connection_id: str, **fields: Any) -> dict:
    bad = set(fields) - _UPDATABLE
    if bad:
        raise ValueError(f"campos nao atualizaveis: {sorted(bad)}")
    sets = ", ".join(f"{k}=%s" for k in fields) + ", updated_at=now()"
    with get_connection() as conn:
        return conn.execute(
            f"UPDATE rt_channel_connections SET {sets} WHERE id::text=%s RETURNING {_CONN_COLS}",
            [*fields.values(), connection_id],
        ).fetchone()


def get_webhook_secret_encrypted(connection_id: str) -> str | None:
    with get_connection() as conn:
        row = conn.execute(
            "SELECT webhook_secret_encrypted FROM rt_channel_connections WHERE id::text=%s",
            (connection_id,),
        ).fetchone()
    return row["webhook_secret_encrypted"] if row else None


def connection_by_matrix_user(matrix_user: str) -> dict | None:
    with get_connection() as conn:
        return conn.execute(
            f"SELECT {_CONN_COLS} FROM rt_channel_connections WHERE matrix_user=%s",
            (matrix_user,),
        ).fetchone()


# --- salas ---------------------------------------------------------------


def bind_room(*, room_id: str, connection_id: str, account_id: int, conversation: str) -> None:
    with get_connection() as conn:
        conn.execute(
            "INSERT INTO rt_channel_rooms (room_id, connection_id, account_id, "
            "conversation_external_id) VALUES (%s,%s,%s,%s) ON CONFLICT (room_id) DO NOTHING",
            (room_id, connection_id, account_id, conversation),
        )


def set_room_conversation(room_id: str, conversation: str) -> None:
    with get_connection() as conn:
        conn.execute(
            "UPDATE rt_channel_rooms SET conversation_external_id=%s WHERE room_id=%s",
            (conversation, room_id),
        )


def room_binding(room_id: str) -> dict | None:
    with get_connection() as conn:
        return conn.execute(
            "SELECT room_id, connection_id::text AS connection_id, account_id, "
            "conversation_external_id FROM rt_channel_rooms WHERE room_id=%s",
            (room_id,),
        ).fetchone()


def room_for_conversation(connection_id: str, conversation: str) -> str | None:
    with get_connection() as conn:
        row = conn.execute(
            "SELECT room_id FROM rt_channel_rooms WHERE connection_id::text=%s "
            "AND conversation_external_id=%s",
            (connection_id, conversation),
        ).fetchone()
    return row["room_id"] if row else None


# --- idempotencia de entrada ---------------------------------------------


def register_message(
    *, account_id: int, connection_id: str, external_id: str, direction: str
) -> bool:
    """True se a mensagem e nova; False se ja foi vista (duplicata)."""
    with get_connection() as conn:
        row = conn.execute(
            "INSERT INTO rt_channel_messages (account_id, connection_id, external_id, direction) "
            "VALUES (%s,%s,%s,%s) ON CONFLICT DO NOTHING RETURNING id",
            (account_id, connection_id, external_id, direction),
        ).fetchone()
    return row is not None


def register_txn(txn_id: str) -> bool:
    with get_connection() as conn:
        row = conn.execute(
            "INSERT INTO rt_channel_appservice_txns (txn_id) VALUES (%s) "
            "ON CONFLICT DO NOTHING RETURNING txn_id",
            (txn_id,),
        ).fetchone()
    return row is not None


# --- outbox --------------------------------------------------------------


def enqueue_outbox(
    *, connection_id: str, account_id: int, kind: str, idempotency_key: str, payload: dict
) -> tuple[dict, bool]:
    """Retorna (linha, criada). Mesma chave => mesma linha, sem duplicar."""
    with get_connection() as conn:
        row = conn.execute(
            "INSERT INTO rt_channel_outbox (connection_id, account_id, kind, idempotency_key, "
            "payload) VALUES (%s,%s,%s,%s,%s) ON CONFLICT (connection_id, kind, idempotency_key) "
            "DO NOTHING RETURNING id::text AS id, status, attempts, external_id, payload",
            (connection_id, account_id, kind, idempotency_key, Jsonb(payload)),
        ).fetchone()
        if row:
            return row, True
        row = conn.execute(
            "SELECT id::text AS id, status, attempts, external_id, payload FROM rt_channel_outbox "
            "WHERE connection_id::text=%s AND kind=%s AND idempotency_key=%s",
            (connection_id, kind, idempotency_key),
        ).fetchone()
        return row, False


def outbox_mark(
    outbox_id: str,
    *,
    status: str,
    external_id: str | None = None,
    error: str = "",
    delay_s: int = 0,
) -> dict:
    with get_connection() as conn:
        return conn.execute(
            "UPDATE rt_channel_outbox SET status=%s, external_id=COALESCE(%s, external_id), "
            "last_error=%s, attempts=attempts+1, "
            "next_attempt_at=now()+make_interval(secs => %s), updated_at=now() "
            "WHERE id::text=%s RETURNING id::text AS id, status, attempts, external_id",
            (status, external_id, error[:200], delay_s, outbox_id),
        ).fetchone()


def due_outbox(kind: str, limit: int = 50) -> list[dict]:
    with get_connection() as conn:
        return conn.execute(
            "SELECT id::text AS id, connection_id::text AS connection_id, account_id, "
            "payload, attempts FROM rt_channel_outbox WHERE kind=%s AND status IN "
            "('queued','failed') AND next_attempt_at <= now() ORDER BY created_at LIMIT %s",
            (kind, limit),
        ).fetchall()


def dead_letters(account_id: int) -> list[dict]:
    with get_connection() as conn:
        return conn.execute(
            "SELECT id::text AS id, connection_id::text AS connection_id, kind, attempts, "
            "last_error FROM rt_channel_outbox WHERE account_id=%s AND status='dead'",
            (account_id,),
        ).fetchall()


# --- auditoria e limites ---------------------------------------------------

_BANNED = ("password", "senha", "cookie", "token", "secret")


def audit(
    *,
    account_id: int,
    action: str,
    actor_id: str = "",
    connection_id: str | None = None,
    detail: dict | None = None,
) -> None:
    detail = detail or {}
    blob = json.dumps(detail).lower()
    if any(b in blob for b in _BANNED):
        raise ValueError("auditoria nao pode conter credenciais")
    with get_connection() as conn:
        conn.execute(
            "INSERT INTO rt_channel_audit (account_id, connection_id, actor_id, action, detail) "
            "VALUES (%s,%s,%s,%s,%s)",
            (account_id, connection_id, actor_id, action, Jsonb(detail)),
        )


def audit_list(connection_id: str) -> list[dict]:
    with get_connection() as conn:
        return conn.execute(
            "SELECT action, actor_id, detail, created_at FROM rt_channel_audit "
            "WHERE connection_id::text=%s ORDER BY id",
            (connection_id,),
        ).fetchall()


def record_login_attempt(account_id: int, provider: str, identifier_hash: str) -> None:
    with get_connection() as conn:
        conn.execute(
            "INSERT INTO rt_channel_login_attempts (account_id, provider, identifier_hash) "
            "VALUES (%s,%s,%s)",
            (account_id, provider, identifier_hash),
        )


def count_login_attempts(account_id: int, provider: str, identifier_hash: str | None) -> int:
    sql = (
        "SELECT count(*) AS n FROM rt_channel_login_attempts WHERE account_id=%s AND provider=%s "
        "AND created_at > now() - interval '1 hour'"
    )
    args: list[Any] = [account_id, provider]
    if identifier_hash is not None:
        sql += " AND identifier_hash=%s"
        args.append(identifier_hash)
    with get_connection() as conn:
        return conn.execute(sql, args).fetchone()["n"]
