"""Aplicacao Matrix propria (appservice) do gateway: Matrix -> eventos normalizados.

Decisao CH-0b: adaptador proprio (ver docs/canais/CH-0b-ADAPTADOR.md). O gateway recebe as
transacoes do Synapse (`PUT /_matrix/app/v1/transactions/{txnId}`), resolve sala -> conexao pelo
mapeamento `rt_channel_rooms` e entrega `InboundMessage` ao servico. Salas desconhecidas ou de
outro tenant sao ignoradas (nunca ha mapeamento cruzado).
"""

from __future__ import annotations

import re
import secrets
from datetime import UTC, datetime
from typing import Any
from urllib.parse import quote

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


_GHOST_RE = re.compile(r"^@(?:instagram|messenger|whatsapp)_(?P<id>[^:]+):")
_LUAR_USER_RE = re.compile(r"^@luar_t(?P<acct>\d+)_c(?P<conn>[0-9a-f]+):")
_BRIDGE_STATE_TYPES = ("m.bridge", "uk.half-shot.bridge")


def ghost_id(mxid: str) -> str | None:
    m = _GHOST_RE.match(mxid or "")
    return m.group("id") if m else None


def is_luar_user(mxid: str) -> bool:
    return bool(_LUAR_USER_RE.match(mxid or ""))


class MatrixHS:
    """Chamadas do appservice do gateway ao Synapse. O usuario Luar da conexao age sempre
    por `user_id=` (impersonacao permitida so no namespace do registro do gateway)."""

    def __init__(self, transport: httpx.AsyncBaseTransport | None = None):
        self._transport = transport

    async def _call(self, method: str, path: str, user_id: str | None = None, body: Any = None):
        try:
            async with httpx.AsyncClient(transport=self._transport, timeout=20) as http:
                return await http.request(
                    method,
                    f"{settings.matrix_homeserver_url}/_matrix/client/v3{path}",
                    params={"user_id": user_id} if user_id else None,
                    json=body,
                    headers={"Authorization": f"Bearer {settings.matrix_as_token}"},
                )
        except httpx.HTTPError as exc:
            raise ProviderError("provider_unavailable") from exc

    async def ensure_user(self, mxid: str) -> None:
        """Registra o usuario Luar da conexao (idempotente); o bridge so convida quem existe."""
        localpart = mxid[1:].split(":", 1)[0]
        resp = await self._call(
            "POST", "/register", body={"type": "m.login.application_service", "username": localpart}
        )
        if resp.status_code >= 400 and resp.json().get("errcode") != "M_USER_IN_USE":
            raise ProviderError("provider_unavailable", f"register {resp.status_code}")

    async def join(self, mxid: str, room_id: str) -> bool:
        resp = await self._call("POST", f"/join/{quote(room_id, safe='')}", mxid, {})
        return resp.status_code < 400

    async def room_info(self, mxid: str, room_id: str) -> tuple[str, str]:
        """(id da conversa no provedor, nome do contato); vazios se a sala nao e um portal."""
        resp = await self._call("GET", f"/rooms/{quote(room_id, safe='')}/state", mxid)
        if resp.status_code >= 400:
            return "", ""
        conversation = name = ""
        for ev in resp.json():
            if ev.get("type") in _BRIDGE_STATE_TYPES:
                conversation = str(ev.get("content", {}).get("channel", {}).get("id") or "")
            elif ev.get("type") == "m.room.member":
                g = ghost_id(ev.get("state_key", ""))
                if g and ev.get("content", {}).get("membership") == "join":
                    name = ev["content"].get("displayname", "") or name
                    conversation = conversation or g
        return conversation, name


async def _on_invite(gateway: Any, event: dict[str, Any]) -> None:
    """Convite do bridge ao usuario Luar de UMA conexao: entra e liga sala -> conversa."""
    matrix = getattr(gateway, "matrix", None)
    mxid = event.get("state_key", "")
    room = event.get("room_id", "")
    if matrix is None or not room or not is_luar_user(mxid):
        return
    conn = store.connection_by_matrix_user(mxid)
    if not conn or store.room_binding(room):
        return
    if not await matrix.join(mxid, room):
        return
    conversation, _ = await matrix.room_info(mxid, room)
    # Sala de gerenciamento do bridge nao tem contato: fica ligada com id vazio (ignorada).
    store.bind_room(
        room_id=room,
        connection_id=conn["id"],
        account_id=conn["account_id"],
        conversation=conversation,
    )


async def handle_transaction(gateway: Any, txn_id: str, events: list[dict[str, Any]]) -> dict:
    """Processa uma transacao do Synapse. Idempotente por txn_id e por event_id."""
    if not store.register_txn(txn_id):
        return {"duplicate": True, "delivered": 0}
    delivered = 0
    for event in events:
        if (
            event.get("type") == "m.room.member"
            and event.get("content", {}).get("membership") == "invite"
        ):
            await _on_invite(gateway, event)
            continue
        room = event.get("room_id")
        binding = store.room_binding(room) if room else None
        if not binding:
            continue
        if not binding["conversation_external_id"]:
            gid = ghost_id(event.get("sender", ""))
            if not gid:
                continue  # sala de gerenciamento, ou contato ainda nao entrou
            store.set_room_conversation(room, gid)
            binding = {**binding, "conversation_external_id": gid}
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
