"""Aplicacao Matrix propria (appservice) do gateway: Matrix -> eventos normalizados.

Decisao CH-0b: adaptador proprio (ver docs/canais/CH-0b-ADAPTADOR.md). O gateway recebe as
transacoes do Synapse (`PUT /_matrix/app/v1/transactions/{txnId}`), resolve sala -> conexao pelo
mapeamento `rt_channel_rooms` e entrega `InboundMessage` ao servico. Salas desconhecidas ou de
outro tenant sao ignoradas (nunca ha mapeamento cruzado).
"""

from __future__ import annotations

import secrets
from datetime import UTC, datetime
from typing import Any

import httpx

from app.channels import store
from app.channels.models import Attachment, ConnectionCtx, InboundMessage
from app.channels.providers.base import ProviderError
from app.config import settings

GHOST_PREFIX = "@"  # fantasmas das bridges: o remetente real e quem NAO e o usuario Luar


def _event_to_message(event: dict[str, Any], binding: dict, conn: dict) -> InboundMessage | None:
    if event.get("type") != "m.room.message":
        return None
    content = event.get("content", {})
    if content.get("msgtype") not in (
        "m.text",
        "m.notice",
        "m.image",
        "m.video",
        "m.audio",
        "m.file",
    ):
        return None
    sender = event.get("sender", "")
    # Mensagem enviada pelo proprio usuario Luar (puppet) = eco/saida; ghost = contato.
    direction = "outgoing_echo" if sender == conn["matrix_user"] else "incoming"
    ts = datetime.fromtimestamp(event.get("origin_server_ts", 0) / 1000, UTC)
    atts: list[Attachment] = []
    mt = content.get("msgtype")
    if mt in ("m.image", "m.video", "m.audio", "m.file") and content.get("url"):
        atts.append(
            Attachment(
                kind={"m.image": "image", "m.video": "video", "m.audio": "audio"}.get(mt, "file"),
                mime=content.get("info", {}).get("mimetype", ""),
                name=content.get("body", ""),
                url=content["url"],  # mxc://; o gateway troca por URL assinada ao entregar
            )
        )
    return InboundMessage(
        connection_id=conn["id"],
        conversation_external_id=binding["conversation_external_id"],
        contact_external_id=sender
        if direction == "incoming"
        else binding["conversation_external_id"],
        contact_name=content.get("fi.mau.displayname", ""),
        message_external_id=event["event_id"],
        direction=direction,
        text="" if atts else content.get("body", ""),
        sent_at=ts,
        reply_to=content.get("m.relates_to", {}).get("m.in_reply_to", {}).get("event_id"),
        attachments=atts,
    )


async def handle_transaction(gateway: Any, txn_id: str, events: list[dict[str, Any]]) -> dict:
    """Processa uma transacao do Synapse. Idempotente por txn_id e por event_id."""
    if not store.register_txn(txn_id):
        return {"duplicate": True, "delivered": 0}
    delivered = 0
    for event in events:
        room = event.get("room_id")
        binding = store.room_binding(room) if room else None
        if not binding:
            continue
        conn = store.get_connection_row(binding["connection_id"], binding["account_id"])
        if not conn:
            continue
        msg = _event_to_message(event, binding, conn)
        if msg and await gateway.inbound(msg):
            delivered += 1
    return {"duplicate": False, "delivered": delivered}


def verify_hs_token(token: str | None) -> bool:
    return bool(settings.matrix_hs_token) and secrets.compare_digest(
        token or "", settings.matrix_hs_token
    )


class MatrixSender:
    """Saida: envia texto na sala do portal como o usuario Luar da conexao (puppet)."""

    def __init__(self, transport: httpx.AsyncBaseTransport | None = None):
        self._transport = transport

    async def __call__(
        self,
        conn: ConnectionCtx,
        conversation_ref: str,
        text: str,
        attachments: list[Attachment],
        reply_to: str | None,
    ) -> str:
        room = store.room_for_conversation(conn.id, conversation_ref)
        if not room:
            raise ProviderError("provider_unavailable", "sala nao mapeada")
        content: dict[str, Any] = {"msgtype": "m.text", "body": text}
        if reply_to:
            content["m.relates_to"] = {"m.in_reply_to": {"event_id": reply_to}}
        txn = secrets.token_hex(8)
        url = (
            f"{settings.matrix_homeserver_url}/_matrix/client/v3/rooms/{room}/send/"
            f"m.room.message/{txn}"
        )
        try:
            async with httpx.AsyncClient(transport=self._transport, timeout=20) as http:
                resp = await http.put(
                    url,
                    params={"user_id": conn.matrix_user},
                    json=content,
                    headers={"Authorization": f"Bearer {settings.matrix_as_token}"},
                )
        except httpx.HTTPError as exc:
            raise ProviderError("provider_unavailable") from exc
        if resp.status_code >= 400:
            raise ProviderError("provider_unavailable", str(resp.status_code))
        return resp.json()["event_id"]
