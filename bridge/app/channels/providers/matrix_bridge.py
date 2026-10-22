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
    StepAttachment,
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

_FIELD_TYPES = {
    "username": "username",
    "password": "password",
    "2fa_code": "2fa_code",
    "select": "select",
    "captcha_code": "captcha_code",
    "phone_number": "phone_number",
    "email": "email",
}
_SECRET_TYPES = ("password", "2fa_code")
# O bridge devolve erro de login como o MESMO passo de novo com texto (ou como dialogo "Try again").
_ERROR_HINTS = (
    ("can't find", "account_not_found"),
    ("cannot find", "account_not_found"),
    ("locked", "account_locked"),
    ("disabled", "account_locked"),
    ("suspended", "account_locked"),
    ("checkpoint", "checkpoint_required"),
    ("incorrect", "wrong_password"),
    ("wrong", "wrong_password"),
    ("rejected", "login_rejected"),
    ("invalid", "login_rejected"),
    ("expired", "timeout"),
)


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
                secret=ftype in _SECRET_TYPES,
                label=f.get("name", "") or "",
                options=[str(o) for o in (f.get("options") or [])],
                default=f.get("default_value") or None,
            )
        )
    return out


def _attachments(raw: list[dict[str, Any]] | None) -> list[StepAttachment]:
    out = []
    for a in raw or []:
        mime = (a.get("info") or {}).get("mimetype", "")
        if a.get("content") and (mime.startswith("image/") or mime.startswith("audio/")):
            out.append(
                StepAttachment(
                    kind="image" if mime.startswith("image/") else "audio",
                    mime=mime,
                    name=a.get("filename", ""),
                    data=a["content"],
                )
            )
    return out


def error_from_text(text: str) -> str | None:
    low = (text or "").lower()
    for needle, code in _ERROR_HINTS:
        if needle in low:
            return code
    return None


def translate_step(raw: dict[str, Any], *, now: datetime | None = None) -> StepView:
    """Passo do bridge -> StepView. Puro, testavel com fixtures (reais e sinteticas)."""
    now = now or datetime.now(UTC)
    stype = raw.get("type")
    step_id = raw.get("step_id", "")
    instructions = (raw.get("instructions") or "").strip()
    if stype == "complete":
        return StepView(
            state=State.CONNECTED,
            step=Step(step_id=step_id, kind="complete"),
            login_id=raw.get("complete", {}).get("user_login_id"),
        )
    if stype == "user_input":
        params = raw.get("user_input", {})
        raw_fields = params.get("fields", [])
        fields = _fields(raw_fields)
        types = {f.type for f in fields}
        atts = _attachments(params.get("attachments"))
        if "2fa_code" in types:
            kind, state, key = "code_2fa", State.AWAITING_2FA, "channels.step.code_2fa"
        elif "captcha_code" in types:
            kind, state, key = "captcha", State.AWAITING_CHALLENGE, "channels.step.captcha"
        elif fields and types == {"select"}:
            kind, state, key = "choice", State.AWAITING_CHALLENGE, "channels.step.choice"
        else:
            kind, state, key = "credentials", State.PENDING_AUTH, "channels.step.credentials"
        return StepView(
            state=state,
            step=Step(
                step_id=step_id,
                kind=kind,  # type: ignore[arg-type]
                instructions_key=key,
                instructions=instructions,
                attachments=atts,
                fields=fields,
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
        return await self._after_submit(conn, cur, kind, raw)

    async def _after_submit(
        self, conn: ConnectionCtx, prev: dict[str, str], kind: str, raw: dict[str, Any]
    ) -> StepView:
        """O bridge real nao devolve HTTP 4xx para senha/codigo errado: repete o passo (ou abre um
        dialogo "Try again") com o motivo em `instructions`. Aqui isso vira `error_code`."""
        for _ in range(2):  # dialogo -> "Try again" -> passo novo (no maximo 2 saltos)
            step_id = raw.get("step_id", "")
            fields = (raw.get("user_input") or {}).get("fields", [])
            opts = fields[0].get("options") if len(fields) == 1 else None
            if (
                raw.get("type") == "user_input"
                and step_id.endswith(".dialog")
                and opts
                and "Try again" in opts
            ):
                hint = error_from_text(raw.get("instructions", "")) or "login_rejected"
                view = await self._resubmit(conn, raw, {fields[0]["id"]: "Try again"})
                if view.step and not view.step.error_code and view.state != State.CONNECTED:
                    view.step.error_code = hint
                return view
            break
        view = self._remember(conn, raw)
        st = view.step
        if raw.get("type") == "user_input" and st and st.kind != "choice":
            repeated = raw.get("step_id") == prev.get("step_id")
            hinted = error_from_text(st.instructions)
            if repeated or hinted:
                by_kind = {"code_2fa": "wrong_code", "captcha": "wrong_captcha"}.get(st.kind)
                if hinted in (None, "wrong_password") and by_kind:
                    hinted = by_kind
                st.error_code = hinted or "wrong_password"
        return view

    async def _resubmit(self, conn: ConnectionCtx, raw: dict[str, Any], data: dict[str, str]):
        pid = raw.get("login_id") or self._proc[conn.id]["process"]
        try:
            nxt = await self._c.step(
                self._user(conn), pid, raw["step_id"], "user_input", data, timeout=60
            )
        except ProvisioningError as exc:
            raise ProviderError(error_code_for(exc)) from exc
        nxt.setdefault("login_id", pid)
        return self._remember(conn, nxt)

    def last_step(self, conn: ConnectionCtx) -> Step | None:
        v = self._last.get(conn.id)
        return v.step if v else None

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
