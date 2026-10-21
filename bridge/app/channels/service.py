"""Orquestracao do gateway de canais: conexao, login, envio (outbox), entrada, estados."""

from __future__ import annotations

import json
import uuid
from datetime import UTC, datetime
from typing import Any

import httpx

from app.channels import signing, store
from app.channels.models import (
    Attachment,
    ConnectionCtx,
    Health,
    InboundMessage,
    Step,
    StepView,
)
from app.channels.providers.base import ProviderAdapter, ProviderError
from app.channels.providers.matrix_bridge import identifier_hash
from app.channels.states import LOGIN_STATES, InvalidTransition, State, check_transition
from app.config import settings
from app.crypto import decrypt, encrypt

RISK_NOTICE_VERSION = "2026-10-20"
BACKOFF_S = [5, 15, 60, 300, 900, 3600, 7200, 14400]


class GatewayError(Exception):
    def __init__(self, status: int, code: str):
        super().__init__(code)
        self.status = status
        self.code = code


def matrix_user_for(account_id: int, connection_id: str) -> str:
    short = connection_id.replace("-", "")[:12]
    return f"@luar_t{account_id}_c{short}:{settings.matrix_server_name}"


def catalog(available: set[str] | None = None) -> dict:
    """Provedores oferecidos. `available` = adaptadores realmente ligados neste gateway."""
    all_providers = [
        {"provider": "instagram", "modes": [{"mode": "experimental", "login": "password"}]},
        {"provider": "messenger", "modes": [{"mode": "experimental", "login": "password"}]},
        {"provider": "tiktok", "modes": [{"mode": "experimental", "login": "qr"}]},
        {"provider": "whatsapp", "modes": [{"mode": "experimental", "login": "qr"}]},
    ]
    return {
        "risk_notice_version": RISK_NOTICE_VERSION,
        "providers": [p for p in all_providers if available is None or p["provider"] in available],
    }


def _ctx(row: dict) -> ConnectionCtx:
    return ConnectionCtx(
        id=row["id"],
        account_id=row["account_id"],
        provider=row["provider"],
        matrix_user=row["matrix_user"],
        gateway_login_id=row["gateway_login_id"],
        external_label=row["external_label"],
    )


def public_view(row: dict, step: Step | None = None, health: Health | None = None) -> dict:
    """Visao devolvida ao Rails/UI: nunca inclui segredo de entrega nem ids de login."""
    return {
        "id": row["id"],
        "account_id": row["account_id"],
        "provider": row["provider"],
        "mode": row["mode"],
        "state": row["state"],
        "external_label": row["external_label"],
        "last_activity_at": row["last_activity_at"],
        "last_error_code": row["last_error_code"],
        "connector_version": row["connector_version"],
        "sync": {
            "status": row["sync_status"],
            "progress": row["sync_progress"],
            "since_days": row["sync_since_days"],
        },
        "health": (health or Health()).model_dump(),
        "step": step.model_dump(mode="json") if step else None,
    }


class Gateway:
    def __init__(
        self,
        adapters: dict[str, ProviderAdapter],
        http: httpx.AsyncClient | None = None,
        matrix: Any = None,
    ):
        self.adapters = adapters
        self._http = http
        self.matrix = matrix  # appservice -> Synapse (registro de usuario, join); None nos testes

    # --- util ----------------------------------------------------------------
    def _row(self, connection_id: str, account_id: int) -> dict:
        row = store.get_connection_row(connection_id, account_id)
        if not row:
            raise GatewayError(404, "not_found")  # outro tenant tambem cai aqui
        return row

    def _adapter(self, provider: str) -> ProviderAdapter:
        try:
            return self.adapters[provider]
        except KeyError as exc:
            raise GatewayError(400, "unsupported_provider") from exc

    def _set_state(self, row: dict, new: State, error: str | None = None, **extra: Any) -> dict:
        old = State(row["state"])
        try:
            check_transition(old, new)
        except InvalidTransition as exc:
            raise GatewayError(409, "invalid_transition") from exc
        fields: dict[str, Any] = {"state": new.value, **extra}
        if error is not None:
            fields["last_error_code"] = error
        return store.update_connection(row["id"], **fields)

    # --- login -----------------------------------------------------------------
    async def connect(
        self, *, account_id: int, provider: str, actor_id: str, consent: dict, flow: str | None
    ) -> dict:
        if not consent.get("accepted"):
            raise GatewayError(400, "consent_required")
        adapter = self._adapter(provider)
        row = store.create_connection(account_id=account_id, provider=provider, login_flow=flow)
        mx = matrix_user_for(account_id, row["id"])
        store.set_matrix_user(row["id"], mx)
        row = self._row(row["id"], account_id)
        if self.matrix is not None:
            try:
                await self.matrix.ensure_user(mx)
            except ProviderError as exc:
                row = self._set_state(row, State.DISCONNECTED, exc.error_code)
                return public_view(
                    row, Step(step_id="", kind="credentials", error_code=exc.error_code)
                )
        store.audit(
            account_id=account_id,
            connection_id=row["id"],
            actor_id=actor_id,
            action="connect_started",
            detail={"provider": provider, "consent_version": str(consent.get("version", ""))},
        )
        try:
            view = await adapter.start_login(_ctx(row), flow)
        except ProviderError as exc:
            row = self._set_state(row, State.DISCONNECTED, exc.error_code)
            return public_view(row, Step(step_id="", kind="credentials", error_code=exc.error_code))
        return self._apply(row, view)

    def _apply(self, row: dict, view: StepView) -> dict:
        err = view.step.error_code if view.step else None
        new = view.state
        if State(row["state"]) != new:
            row = self._set_state(row, new, err or "")
        elif err:
            row = store.update_connection(row["id"], last_error_code=err)
        if new == State.CONNECTED:
            if view.login_id:
                row = store.update_connection(row["id"], gateway_login_id=view.login_id)
            store.audit(account_id=row["account_id"], connection_id=row["id"], action="connected")
        return public_view(row, view.step)

    def _check_attempts(self, row: dict, identifier: str) -> str:
        ih = identifier_hash(row["account_id"], identifier)
        per_id = store.count_login_attempts(row["account_id"], row["provider"], ih)
        per_tenant = store.count_login_attempts(row["account_id"], row["provider"], None)
        if (
            per_id >= settings.channels_login_attempts_per_hour
            or per_tenant >= settings.channels_login_attempts_per_tenant_hour
        ):
            raise GatewayError(429, "too_many_attempts")
        return ih

    async def step(
        self, *, account_id: int, connection_id: str, step_id: str, kind: str, data: dict
    ) -> dict:
        row = self._row(connection_id, account_id)
        if State(row["state"]) not in LOGIN_STATES:
            raise GatewayError(409, "not_in_login")
        if kind == "credentials":
            ih = self._check_attempts(row, str(data.get("username", "")))
            store.record_login_attempt(account_id, row["provider"], ih)
        adapter = self._adapter(row["provider"])
        try:
            view = await adapter.submit_step(_ctx(row), step_id, kind, data)
        except ProviderError as exc:
            attempts = None
            if kind == "credentials":
                used = store.count_login_attempts(
                    account_id,
                    row["provider"],
                    identifier_hash(account_id, data.get("username", "")),
                )
                attempts = max(0, settings.channels_login_attempts_per_hour - used)
            row = store.update_connection(row["id"], last_error_code=exc.error_code)
            # mantem os campos do passo para o usuario tentar de novo (sem isso a tela fica sem inputs)
            last = getattr(adapter, "last_step", lambda _c: None)(_ctx(row))
            if last is not None:
                err_step = last.model_copy(
                    update={"error_code": exc.error_code, "attempts_left": attempts}
                )
            else:
                err_step = Step(
                    step_id=step_id,
                    kind=kind,  # type: ignore[arg-type]
                    error_code=exc.error_code,
                    attempts_left=attempts,
                )
            return public_view(row, err_step)
        return self._apply(row, view)

    async def status(self, *, account_id: int, connection_id: str) -> dict:
        row = self._row(connection_id, account_id)
        step = None
        if State(row["state"]) in LOGIN_STATES:
            try:
                view = await self._adapter(row["provider"]).poll_step(_ctx(row))
                return self._apply(row, view)
            except ProviderError as exc:
                row = self._set_state(row, State.DISCONNECTED, exc.error_code)
        health = await self._adapter(row["provider"]).health(_ctx(row))
        return public_view(row, step, health)

    async def cancel(self, *, account_id: int, connection_id: str) -> dict:
        row = self._row(connection_id, account_id)
        await self._adapter(row["provider"]).cancel_login(_ctx(row))
        if State(row["state"]) in LOGIN_STATES:
            row = self._set_state(row, State.DISCONNECTED)
        return public_view(row)

    async def disconnect(self, *, account_id: int, connection_id: str, actor_id: str) -> dict:
        return await self._end(account_id, connection_id, actor_id, State.DISCONNECTED)

    async def revoke(self, *, account_id: int, connection_id: str, actor_id: str) -> dict:
        return await self._end(account_id, connection_id, actor_id, State.REVOKED)

    async def _end(self, account_id: int, connection_id: str, actor_id: str, to: State) -> dict:
        row = self._row(connection_id, account_id)
        adapter = self._adapter(row["provider"])
        await adapter.cancel_login(_ctx(row))
        try:
            await adapter.logout(_ctx(row))
        except ProviderError as exc:
            raise GatewayError(502, exc.error_code) from exc
        row = self._set_state(row, to, "", gateway_login_id=None)
        store.audit(
            account_id=account_id,
            connection_id=row["id"],
            actor_id=actor_id,
            action="disconnected" if to == State.DISCONNECTED else "revoked",
        )
        return public_view(row)

    async def reauth(self, *, account_id: int, connection_id: str, actor_id: str) -> dict:
        row = self._row(connection_id, account_id)
        if State(row["state"]) not in (State.REAUTH_REQUIRED, State.DISCONNECTED):
            raise GatewayError(409, "invalid_transition")
        adapter = self._adapter(row["provider"])
        row = self._set_state(row, State.PENDING_AUTH, "")
        store.audit(
            account_id=account_id, connection_id=row["id"], actor_id=actor_id, action="reauth"
        )
        try:
            view = await adapter.start_login(_ctx(row), row["login_flow"])
        except ProviderError as exc:
            row = self._set_state(row, State.REAUTH_REQUIRED, exc.error_code)
            return public_view(row, Step(step_id="", kind="credentials", error_code=exc.error_code))
        return self._apply(row, view)

    def register_login(self, connection_id: str, login_id: str, label: str = "") -> None:
        """Chamado quando o bridge confirma o login (evento do appservice / health)."""
        row = store.get_connection_row(connection_id)
        if not row:
            return
        fields: dict[str, Any] = {"gateway_login_id": login_id, "last_activity_at": _now()}
        if label:
            fields["external_label"] = label
        store.update_connection(connection_id, **fields)

    # --- entrega (Rails) --------------------------------------------------------
    def set_delivery(
        self, *, account_id: int, connection_id: str, webhook_url: str, secret: str, inbox_ref: str
    ) -> dict:
        row = self._row(connection_id, account_id)
        row = store.update_connection(
            row["id"],
            webhook_url=webhook_url,
            webhook_secret_encrypted=encrypt(secret),
            inbox_ref=inbox_ref,
        )
        return public_view(row)

    # --- entrada ----------------------------------------------------------------
    async def inbound(self, msg: InboundMessage) -> bool:
        """Retorna True se a mensagem foi enfileirada; False se duplicata/descartada."""
        row = store.get_connection_row(msg.connection_id)
        if not row or State(row["state"]) in (State.REVOKED, State.DISCONNECTED):
            return False
        new = store.register_message(
            account_id=row["account_id"],
            connection_id=row["id"],
            external_id=msg.message_external_id,
            direction=msg.direction,
        )
        if not new:
            return False
        store.update_connection(row["id"], last_activity_at=_now())
        event = {
            "event_id": str(uuid.uuid4()),
            "type": "message.created",
            "account_id": row["account_id"],
            "connection_id": row["id"],
            "channel": row["provider"],
            "provider_mode": "experimental",
            "occurred_at": _now().isoformat(),
            "conversation": {
                "external_id": msg.conversation_external_id,
                "contact": {
                    "external_id": msg.contact_external_id,
                    "name": msg.contact_name,
                    "username": msg.contact_username,
                    "avatar_url": msg.avatar_url,
                },
            },
            "message": {
                "external_id": msg.message_external_id,
                "direction": msg.direction,
                "text": msg.text,
                "sent_at": msg.sent_at.isoformat(),
                "reply_to": msg.reply_to,
                "attachments": [a.model_dump() for a in msg.attachments],
            },
        }
        store.enqueue_outbox(
            connection_id=row["id"],
            account_id=row["account_id"],
            kind="webhook",
            idempotency_key=event["event_id"],
            payload=event,
        )
        return True

    async def on_state_event(self, connection_id: str, new: State, error: str = "") -> None:
        row = store.get_connection_row(connection_id)
        if not row or State(row["state"]) == new:
            return
        try:
            row = self._set_state(row, new, error)
        except GatewayError:
            return
        store.enqueue_outbox(
            connection_id=row["id"],
            account_id=row["account_id"],
            kind="webhook",
            idempotency_key=str(uuid.uuid4()),
            payload={
                "event_id": str(uuid.uuid4()),
                "type": "connection.state",
                "account_id": row["account_id"],
                "connection_id": row["id"],
                "channel": row["provider"],
                "provider_mode": "experimental",
                "occurred_at": _now().isoformat(),
                "state": {"state": new.value, "error_code": error},
            },
        )

    # EventSink (usado pelos adaptadores)
    async def on_message(self, msg: InboundMessage) -> None:
        await self.inbound(msg)

    async def on_session_invalid(self, connection_id: str, error_code: str) -> None:
        await self.on_state_event(connection_id, State.REAUTH_REQUIRED, error_code)

    async def on_degraded(self, connection_id: str, error_code: str) -> None:
        await self.on_state_event(connection_id, State.DEGRADED, error_code)

    async def on_recovered(self, connection_id: str) -> None:
        await self.on_state_event(connection_id, State.CONNECTED, "")

    # --- saida -----------------------------------------------------------------
    async def send(
        self,
        *,
        account_id: int,
        connection_id: str,
        idempotency_key: str,
        conversation_ref: str,
        text: str,
        attachments: list[dict] | None = None,
        reply_to: str | None = None,
    ) -> dict:
        row = self._row(connection_id, account_id)
        if State(row["state"]) not in (State.CONNECTED, State.DEGRADED):
            raise GatewayError(409, "not_connected")  # reauth_required pausa o envio
        out, created = store.enqueue_outbox(
            connection_id=row["id"],
            account_id=account_id,
            kind="send",
            idempotency_key=idempotency_key,
            payload={
                "conversation_ref": conversation_ref,
                "text": text,
                "attachments": attachments or [],
                "reply_to": reply_to,
            },
        )
        if not created and out["status"] == "sent":
            return {"outbox_id": out["id"], "status": "sent", "external_id": out["external_id"]}
        return await self._deliver_send(row, out)

    async def _deliver_send(self, row: dict, out: dict) -> dict:
        p = out["payload"]
        try:
            ext = await self._adapter(row["provider"]).send(
                _ctx(row),
                p["conversation_ref"],
                p["text"],
                [Attachment(**a) for a in p.get("attachments", [])],
                p.get("reply_to"),
            )
        except ProviderError as exc:
            if exc.error_code in ("session_invalid", "wrong_password", "reauth_required"):
                await self.on_session_invalid(row["id"], exc.error_code)
            dead = out["attempts"] + 1 >= settings.channels_webhook_max_attempts
            res = store.outbox_mark(
                out["id"],
                status="dead" if dead else "failed",
                error=exc.error_code,
                delay_s=BACKOFF_S[min(out["attempts"], len(BACKOFF_S) - 1)],
            )
            return {"outbox_id": res["id"], "status": res["status"], "external_id": None}
        # Registra o eco para nao virar mensagem duplicada quando o provedor devolver o evento.
        store.register_message(
            account_id=row["account_id"],
            connection_id=row["id"],
            external_id=ext,
            direction="outgoing_echo",
        )
        res = store.outbox_mark(out["id"], status="sent", external_id=ext)
        return {"outbox_id": res["id"], "status": "sent", "external_id": ext}

    # --- entrega de webhooks (worker) -------------------------------------------
    async def flush_webhooks(self) -> dict:
        sent = failed = dead = 0
        for item in store.due_outbox("webhook"):
            row = store.get_connection_row(item["connection_id"])
            enc = store.get_webhook_secret_encrypted(item["connection_id"])
            if not row or not row["webhook_url"] or not enc:
                continue  # Rails ainda nao registrou o destino: segura na fila
            body = json.dumps(item["payload"], separators=(",", ":")).encode()
            hdrs = signing.headers(decrypt(enc), item["payload"]["event_id"], body)
            try:
                http = self._http or httpx.AsyncClient(timeout=10)
                resp = await http.post(row["webhook_url"], content=body, headers=hdrs)
                ok = resp.status_code < 300
            except httpx.HTTPError:
                ok = False
            if ok:
                store.outbox_mark(item["id"], status="sent")
                sent += 1
                continue
            is_dead = item["attempts"] + 1 >= settings.channels_webhook_max_attempts
            store.outbox_mark(
                item["id"],
                status="dead" if is_dead else "failed",
                error="webhook_rejected",
                delay_s=BACKOFF_S[min(item["attempts"], len(BACKOFF_S) - 1)],
            )
            dead += is_dead
            failed += not is_dead
        return {"sent": sent, "failed": failed, "dead": dead}

    async def retry_sends(self) -> int:
        n = 0
        for item in store.due_outbox("send"):
            row = store.get_connection_row(item["connection_id"])
            if row and State(row["state"]) in (State.CONNECTED, State.DEGRADED):
                out = {**item, "payload": item["payload"]}
                res = await self._deliver_send(row, out)
                n += res["status"] == "sent"
        return n


def _now() -> datetime:
    return datetime.now(UTC)
