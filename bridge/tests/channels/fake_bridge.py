"""Bridge falso: simula a API de provisionamento do mautrix bridgev2 com fixtures dos passos.

Roteiros (por flow):
  android / messenger-lite: credenciais -> [2fa_code] -> complete
      senha "bad" = erro; "locked" = conta bloqueada; "2fa" exige codigo 123456;
      "challenge" = espera de aprovacao no aplicativo (libera com `approve = True`).
  qr / phone: display_and_wait(qr) com QR novo a cada chamada -> complete quando `qr_scanned`.
Guarda os corpos recebidos so para os testes de varredura de vazamento.
"""

from __future__ import annotations

import json

import httpx

SECRET = "segredo-provisionamento-teste"


class FakeBridge:
    def __init__(self, allowed_user_prefix: str = "@luar_"):
        self.allowed = allowed_user_prefix
        self.procs: dict[str, dict] = {}
        self.logins: dict[str, list[str]] = {}
        self.calls: list[tuple[str, str]] = []
        self.bodies: list[str] = []
        self.qr_n = 0
        self.approve = False
        self.qr_scanned = False
        self.n = 0

    def transport(self) -> httpx.MockTransport:
        return httpx.MockTransport(self._handle)

    @staticmethod
    def _err(status: int, code: str, msg: str = "") -> httpx.Response:
        return httpx.Response(status, json={"errcode": code, "error": msg})

    def _handle(self, req: httpx.Request) -> httpx.Response:
        path = req.url.path.split("/_matrix/provision", 1)[1]
        user = req.url.params.get("user_id", "")
        self.calls.append((req.method, path))
        if req.headers.get("authorization") != f"Bearer {SECRET}":
            return self._err(401, "M_UNKNOWN_TOKEN")
        if not user.startswith(self.allowed):
            return self._err(403, "M_FORBIDDEN", "user not allowed")
        body = json.loads(req.content) if req.content else {}
        self.bodies.append(req.content.decode() if req.content else "")
        parts = path.strip("/").split("/")
        if path == "/v3/login/flows":
            return httpx.Response(200, json={"flows": [{"id": "android"}, {"id": "qr"}]})
        if parts[:3] == ["v3", "login", "start"]:
            self.n += 1
            pid = f"proc{self.n}"
            self.procs[pid] = {"flow": parts[3], "user": user, "stage": "start"}
            return httpx.Response(200, json=self._step(pid))
        if parts[:3] == ["v3", "login", "step"]:
            pid = parts[3]
            proc = self.procs.get(pid)
            if not proc or proc["user"] != user:
                return self._err(404, "M_NOT_FOUND", "login process not found")
            return self._advance(pid, proc, body)
        if parts[:3] == ["v3", "login", "cancel"]:
            self.procs.pop(parts[3], None)
            return httpx.Response(200, json={})
        if path == "/v3/logins":
            return httpx.Response(200, json={"login_ids": self.logins.get(user, [])})
        if parts[:2] == ["v3", "logout"]:
            ids = self.logins.get(user, [])
            if parts[2] not in ids:
                return self._err(404, "M_NOT_FOUND")
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
                    "display_and_wait": {"type": "qr", "data": f"2@qr-{self.qr_n}"},
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
        lid = f"login-{pid}"
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
        if st == "start" and not qr_flow:
            pw = body.get("password", "")
            if pw == "bad":
                return self._err(400, "FI.MAU.META_CAA_FAILED", "wrong password")
            if pw == "locked":
                return self._err(400, "FI.MAU.X", "account locked")
            proc["stage"] = {"2fa": "2fa", "challenge": "challenge"}.get(pw, "done")
        elif st == "2fa":
            if body.get("verification_code") != "123456":
                return self._err(400, "FI.MAU.META_CAA_FAILED", "bad code")
            proc["stage"] = "done"
        elif st == "challenge":
            if self.approve:
                proc["stage"] = "done"
        elif qr_flow:
            proc["stage"] = "done" if self.qr_scanned else "start"
        return httpx.Response(200, json=self._step(pid))
