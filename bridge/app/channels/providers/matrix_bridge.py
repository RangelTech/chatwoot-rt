"""Adaptador dos bridges mautrix (Instagram, Messenger, WhatsApp) via API de provisionamento.

Traduz os passos do bridgev2 (`user_input`, `display_and_wait`, `cookies`, `complete`) para os
passos do Luar. Passos de cookies/webview NUNCA sao apresentados: viram `unsupported_step`.
"""

from __future__ import annotations

import hashlib
from datetime import UTC, datetime, timedelta
from typing import Any

from app.channels.models import (
    Attachment,
    ConnectionCtx,
    Health,
    QrInfo,
    Step,
    StepField,
    StepView,
    WaitInfo,
)
from app.channels.providers.base import ProviderError
from app.channels.provisioning import ProvisioningClient, ProvisioningError
from app.channels.states import State

# Fluxos permitidos por provedor. Os de cookie/webview ficam de fora de proposito.
DEFAULT_FLOW = {"instagram": "android", "messenger": "messenger-lite", "whatsapp": "qr"}
ALLOWED_FLOWS = {
    "instagram": {"android"},
    "messenger": {"messenger-lite", "messenger-lite-android"},
    "whatsapp": {"qr", "phone"},
}
QR_TTL_S = 20

_ERRCODE_MAP = {
    "FI.MAU.META_CAA_FAILED": "wrong_password",
    "FI.MAU.META_UNSUPPORTED_CAA_STEP": "unsupported_step",
    "FI.MAU.META_CAA_CLIENT_HTTP_FAILED": "provider_unavailable",
    "FI.MAU.IG_MISSING_AUTH": "wrong_password",
    "TIMEOUT": "timeout",
    "UNAVAILABLE": "provider_unavailable",
    "M_FORBIDDEN": "provider_unavailable",
}

_FIELD_TYPES = {"username": "username", "password": "password", "2fa_code": "2fa_code"}


def error_code_for(exc: ProvisioningError, hint: str | None = None) -> str:
    if exc.errcode in _ERRCODE_MAP:
        return _ERRCODE_MAP[exc.errcode]
    low = exc.message.lower()
    if "locked" in low or "disabled" in low or "suspended" in low:
        return "account_locked"
    if "checkpoint" in low or "challenge" in low:
        return "checkpoint_required"
    return hint or "provider_unavailable"


def _fields(raw: list[dict[str, Any]]) -> list[StepField]:
    out = []
    for f in raw:
        ftype = _FIELD_TYPES.get(f.get("type", ""), "text")
        out.append(
            StepField(
                id=f["id"],
                type=ftype,
                label_key=f"channels.field.{f['id']}",
                secret=ftype in ("password", "2fa_code"),
            )
        )
    return out


def translate_step(raw: dict[str, Any], *, now: datetime | None = None) -> StepView:
    """Passo do bridge -> StepView. Puro, testavel com fixtures."""
    now = now or datetime.now(UTC)
    stype = raw.get("type")
    step_id = raw.get("step_id", "")
    if stype == "complete":
        return StepView(
            state=State.CONNECTED,
            step=Step(step_id=step_id, kind="complete"),
            login_id=raw.get("complete", {}).get("user_login_id"),
        )
    if stype == "user_input":
        fields = raw.get("user_input", {}).get("fields", [])
        if any(f.get("type") == "2fa_code" for f in fields):
            return StepView(
                state=State.AWAITING_2FA,
                step=Step(
                    step_id=step_id,
                    kind="code_2fa",
                    instructions_key="channels.step.code_2fa",
                    fields=_fields(fields),
                ),
            )
        return StepView(
            state=State.PENDING_AUTH,
            step=Step(
                step_id=step_id,
                kind="credentials",
                instructions_key="channels.step.credentials",
                fields=_fields(fields),
            ),
        )
    if stype == "display_and_wait":
        params = raw.get("display_and_wait", {})
        dtype = params.get("type")
        if dtype == "qr":
            return StepView(
                state=State.PENDING_AUTH,
                step=Step(
                    step_id=step_id,
                    kind="qr",
                    instructions_key="channels.step.qr",
                    qr=QrInfo(
                        data=params.get("data", ""),
                        expires_at=now + timedelta(seconds=QR_TTL_S),
                        refresh_after_s=QR_TTL_S,
                    ),
                    wait=WaitInfo(can_cancel=True),
                ),
            )
        if dtype == "code":
            return StepView(
                state=State.PENDING_AUTH,
                step=Step(
                    step_id=step_id,
                    kind="pairing_code",
                    instructions_key="channels.step.pairing_code",
                    pairing_code=params.get("data", ""),
                    wait=WaitInfo(can_cancel=True),
                ),
            )
        return StepView(
            state=State.AWAITING_CHALLENGE,
            step=Step(
                step_id=step_id,
                kind="await_approval",
                instructions_key="channels.step.await_approval",
                wait=WaitInfo(poll_after_s=3, can_cancel=bool(params.get("can_cancel", True))),
            ),
        )
    # cookies, webauthn, client_http (webview) etc.: fora do escopo (sem cookie).
    return StepView(
        state=State.PENDING_AUTH,
        step=Step(step_id=step_id, kind="credentials", error_code="unsupported_step"),
    )


def identifier_hash(account_id: int, identifier: str) -> str:
    return hashlib.sha256(f"{account_id}:{identifier.strip().lower()}".encode()).hexdigest()


class MatrixBridgeAdapter:
    """Um adaptador por provedor; o processo do bridge e compartilhado entre tenants."""

    def __init__(self, name: str, client: ProvisioningClient, sender: Any = None):
        self.name = name
        self._c = client
        self._sender = sender  # envia texto na sala Matrix (appservice); injetado pelo gateway
        # Estado de login em andamento por conexao. NUNCA guarda senha: so ids do bridge.
        self._proc: dict[str, dict[str, str]] = {}
        self._last: dict[str, StepView] = {}

    def _user(self, conn: ConnectionCtx) -> str:
        if not conn.matrix_user:
            raise ProviderError("provider_unavailable", "conexao sem usuario matrix")
        return conn.matrix_user

    def _remember(self, conn: ConnectionCtx, raw: dict[str, Any]) -> StepView:
        pid = raw.get("login_id") or self._proc.get(conn.id, {}).get("process", "")
        self._proc[conn.id] = {
            "process": pid,
            "step_id": raw.get("step_id", ""),
            "type": raw.get("type", ""),
        }
        view = translate_step(raw)
        self._last[conn.id] = view
        return view

    async def start_login(self, conn: ConnectionCtx, flow: str | None) -> StepView:
        flow = flow or DEFAULT_FLOW[self.name]
        if flow not in ALLOWED_FLOWS[self.name]:
            raise ProviderError("unsupported_step", f"fluxo {flow} nao permitido")
        try:
            raw = await self._c.start(self._user(conn), flow)
        except ProvisioningError as exc:
            raise ProviderError(error_code_for(exc)) from exc
        return self._remember(conn, raw)

    async def submit_step(
        self, conn: ConnectionCtx, step_id: str, kind: str, data: dict[str, str]
    ) -> StepView:
        cur = self._proc.get(conn.id)
        if not cur:
            raise ProviderError("timeout", "sem login em andamento")
        stype = "user_input" if cur["type"] == "user_input" else cur["type"]
        try:
            raw = await self._c.step(
                self._user(conn), cur["process"], cur["step_id"], stype, data, timeout=60
            )
        except ProvisioningError as exc:
            code = error_code_for(exc, "wrong_code" if kind == "code_2fa" else "wrong_password")
            if kind == "code_2fa" and code == "wrong_password":
                code = "wrong_code"
            raise ProviderError(code) from exc
        raw.setdefault("login_id", cur["process"])
        return self._remember(conn, raw)

    async def poll_step(self, conn: ConnectionCtx) -> StepView:
        cur = self._proc.get(conn.id)
        if not cur:
            raise ProviderError("timeout", "sem login em andamento")
        if cur["type"] != "display_and_wait":
            return self._last[conn.id]
        try:
            raw = await self._c.step(
                self._user(conn),
                cur["process"],
                cur["step_id"],
                "display_and_wait",
                {},
                timeout=25,
            )
        except ProvisioningError as exc:
            if exc.errcode == "TIMEOUT":
                return self._last[conn.id]
            raise ProviderError(error_code_for(exc, "timeout")) from exc
        raw.setdefault("login_id", cur["process"])
        return self._remember(conn, raw)

    async def cancel_login(self, conn: ConnectionCtx) -> None:
        cur = self._proc.pop(conn.id, None)
        self._last.pop(conn.id, None)
        if cur:
            try:
                await self._c.cancel(self._user(conn), cur["process"])
            except ProvisioningError:
                pass  # processo ja expirou no bridge; nada a limpar

    async def logout(self, conn: ConnectionCtx) -> None:
        if not conn.gateway_login_id:
            return
        try:
            await self._c.logout(self._user(conn), conn.gateway_login_id)
        except ProvisioningError as exc:
            if exc.status != 404:
                raise ProviderError(error_code_for(exc)) from exc

    async def send(
        self,
        conn: ConnectionCtx,
        conversation_ref: str,
        text: str,
        attachments: list[Attachment],
        reply_to: str | None,
    ) -> str:
        if self._sender is None:
            raise ProviderError("provider_unavailable", "sem canal de saida matrix")
        return await self._sender(conn, conversation_ref, text, attachments, reply_to)

    async def sync(self, conn: ConnectionCtx, since_days: int) -> None:
        return None  # backfill e feito pelo proprio bridge (config backfill); progresso via eventos

    async def health(self, conn: ConnectionCtx) -> Health:
        try:
            logins = await self._c.logins(self._user(conn))
        except ProvisioningError:
            return Health(process=False, session=False, io=False)
        ok = bool(conn.gateway_login_id) and conn.gateway_login_id in logins
        return Health(process=True, session=ok, io=ok)
