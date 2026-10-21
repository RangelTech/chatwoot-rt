"""Simulador de canais para QA/CDP (CHANNELS_SIMULATOR=1): passos de login deterministicos.

Fala a API de provisionamento do mautrix em memoria (sem rede, sem conta real) e troca o worker do
TikTok pelo driver fake. Nunca liga a nada externo. Roteiro (senha digitada decide):
  bad -> senha errada | locked -> conta bloqueada | 2fa -> pede codigo (123456)
  challenge -> "confirme no app", aprova sozinho | qualquer outra -> conecta
QR (WhatsApp/TikTok): QR novo a cada passo, "escaneado" sozinho apos SCAN_AFTER_S.
O endpoint /sim/inbound so existe com o simulador ligado. Nao use em producao real.
"""

from __future__ import annotations

import json
import time

import httpx

from app.channels.models import Attachment, ConnectionCtx

SECRET = "simulador"
CODE = "123456"
APPROVE_AFTER_S = 8.0
SCAN_AFTER_S = 20.0


class SimBridge:
    def __init__(
        self, approve_after_s: float = APPROVE_AFTER_S, scan_after_s: float = SCAN_AFTER_S
    ):
        self.approve_after_s = approve_after_s
        self.scan_after_s = scan_after_s
        self.procs: dict[str, dict] = {}
        self.logins: dict[str, list[str]] = {}
        self.n = 0
        self.qr_n = 0

    def transport(self) -> httpx.MockTransport:
        return httpx.MockTransport(self._handle)

    @staticmethod
    def _err(status: int, code: str, msg: str = "") -> httpx.Response:
        return httpx.Response(status, json={"errcode": code, "error": msg})

    def _handle(self, req: httpx.Request) -> httpx.Response:
        path = req.url.path.split("/_matrix/provision", 1)[1]
        user = req.url.params.get("user_id", "")
        body = json.loads(req.content) if req.content else {}
        parts = path.strip("/").split("/")
        if path == "/v3/login/flows":
            return httpx.Response(200, json={"flows": [{"id": "android"}, {"id": "qr"}]})
        if parts[:3] == ["v3", "login", "start"]:
            self.n += 1
            pid = f"sim{self.n}"
            self.procs[pid] = {"flow": parts[3], "user": user, "stage": "start", "t0": time.time()}
            return httpx.Response(200, json=self._step(pid))
        if parts[:3] == ["v3", "login", "step"]:
            proc = self.procs.get(parts[3])
            if not proc or proc["user"] != user:
                return self._err(404, "M_NOT_FOUND", "login process not found")
            return self._advance(parts[3], proc, body)
        if parts[:3] == ["v3", "login", "cancel"]:
            self.procs.pop(parts[3], None)
            return httpx.Response(200, json={})
        if path == "/v3/logins":
            return httpx.Response(200, json={"login_ids": self.logins.get(user, [])})
        if parts[:2] == ["v3", "logout"]:
            ids = self.logins.get(user, [])
            if parts[2] in ids:
                ids.remove(parts[2])
            return httpx.Response(200, json={})
        return self._err(404, "M_NOT_FOUND")

    def _step(self, pid: str) -> dict:
        proc = self.procs[pid]
        st = proc["stage"]
        base = {"login_id": pid, "txn_id": "t", "instructions": ""}
        if proc["flow"] in ("qr", "phone"):
            if st == "start":
                self.qr_n += 1
                return {
                    **base,
                    "type": "display_and_wait",
                    "step_id": "fi.mau.whatsapp.login.qr",
                    "display_and_wait": {
                        "type": "qr",
                        "data": f"https://wa.me/settings/linked_devices#sim-{self.qr_n}",
                    },
                }
        else:
            if st == "start":
                return {
                    **base,
                    "type": "user_input",
                    "step_id": "fi.mau.meta.instagram.credentials",
                    "user_input": {
                        "fields": [
                            {"type": "username", "id": "username"},
                            {"type": "password", "id": "password"},
                        ]
                    },
                }
            if st == "2fa":
                return {
                    **base,
                    "type": "user_input",
                    "step_id": "fi.mau.meta.instagram.web_two_factor",
                    "user_input": {"fields": [{"type": "2fa_code", "id": "verification_code"}]},
                }
            if st == "challenge":
                return {
                    **base,
                    "type": "display_and_wait",
                    "step_id": "fi.mau.meta.instagram.web_challenge",
                    "display_and_wait": {"type": "nothing", "can_cancel": True},
                }
        lid = f"sim-login-{pid}"
        ids = self.logins.setdefault(proc["user"], [])
        if lid not in ids:
            ids.append(lid)
        return {
            **base,
            "type": "complete",
            "step_id": "fi.mau.meta.complete",
            "complete": {"user_login_id": lid},
        }

    def _advance(self, pid: str, proc: dict, body: dict) -> httpx.Response:
        st = proc["stage"]
        qr_flow = proc["flow"] in ("qr", "phone")
        age = time.time() - proc["t0"]
        if st == "start" and not qr_flow:
            pw = body.get("password", "")
            if pw == "bad":
                return self._err(400, "FI.MAU.META_CAA_FAILED", "wrong password")
            if pw == "locked":
                return self._err(400, "FI.MAU.X", "account locked")
            proc["stage"] = {"2fa": "2fa", "challenge": "challenge"}.get(pw, "done")
            proc["t0"] = time.time()
        elif st == "2fa":
            if body.get("verification_code") != CODE:
                return self._err(400, "FI.MAU.META_CAA_FAILED", "bad code")
            proc["stage"] = "done"
        elif st == "challenge":
            if age >= self.approve_after_s:
                proc["stage"] = "done"
        elif qr_flow:
            if age >= self.scan_after_s:
                proc["stage"] = "done"
        return httpx.Response(200, json=self._step(pid))


class SimSender:
    """Saida simulada: devolve ids e guarda o que foi enviado (inspecao em QA)."""

    def __init__(self):
        self.sent: list[tuple[str, str, str]] = []
        self.n = 0

    async def __call__(
        self,
        conn: ConnectionCtx,
        conversation_ref: str,
        text: str,
        attachments: list[Attachment],
        reply_to: str | None,
    ) -> str:
        self.n += 1
        self.sent.append((conn.id, conversation_ref, text))
        return f"$sim-out-{self.n}"
