"""Registro e deduplicação de eventos de canal.

O corpo cru é gravado antes de qualquer parsing — provedor não-oficial muda
envelope sem avisar, e perder o evento junto com o parser não é aceitável.
A deduplicação é feita no banco (índice único), não em memória: o Cloud Run
sobe e desce instâncias, e um dedup em memória não sobrevive a isso.
"""

import logging

from psycopg.errors import UniqueViolation

from app.db import get_connection

logger = logging.getLogger(__name__)


def record_event(
    *,
    tenant_id: str | None,
    channel_id: str | None,
    provider: str,
    dedup_key: str | None,
    raw_body: str,
    state: str = "received",
    detail: str = "",
    direction: str = "in",
) -> dict | None:
    """Grava o evento. Devolve None quando é duplicata já processada."""
    with get_connection() as conn:
        try:
            return conn.execute(
                """INSERT INTO channel_events (tenant_id, channel_id, provider, dedup_key,
                                               raw_body, state, detail, direction)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING *""",
                (
                    tenant_id,
                    channel_id,
                    provider,
                    dedup_key,
                    raw_body[:20_000],
                    state,
                    detail[:1_000],
                    direction,
                ),
            ).fetchone()
        except UniqueViolation:
            return None


def update_event(event_id: str, *, state: str, detail: str = "") -> None:
    try:
        with get_connection() as conn:
            conn.execute(
                """UPDATE channel_events SET state = %s, detail = %s, updated_at = now()
                    WHERE id = %s""",
                (state, detail[:1_000], event_id),
            )
    except Exception:  # noqa: BLE001 — auditoria nunca derruba o fluxo
        logger.exception("falha ao atualizar evento %s", event_id)
