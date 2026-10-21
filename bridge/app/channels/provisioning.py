"""Cliente da API de provisionamento do mautrix bridgev2 (`/_matrix/provision/v3`).

Rotas confirmadas em `mautrix/go bridgev2/matrix/provisioning.go`:
  GET  /v3/login/flows
  POST /v3/login/start/{flowID}
  POST /v3/login/step/{loginProcessID}/{stepID}/{stepType}   (user_input, display_and_wait)
  POST /v3/login/cancel/{loginProcessID}
  GET  /v3/logins            POST /v3/logout/{loginID}      GET /v3/whoami
Autenticacao: `Authorization: Bearer <shared_secret>` + `?user_id=<mxid>`; o bridge so aceita
usuarios que casam com `bridge.permissions` (padrao @luar_t<conta>_c<id>:<servidor>).
Senhas e codigos so trafegam no corpo destas chamadas; nada e registrado em log.
"""

from __future__ import annotations

from typing import Any

import httpx


class ProvisioningError(Exception):
    def __init__(self, status: int, errcode: str, message: str = ""):
        super().__init__(f"{status} {errcode}")
        self.status = status
        self.errcode = errcode
        self.message = message  # texto do bridge; nunca inclui o corpo enviado


class ProvisioningClient:
    def __init__(
        self,
        base_url: str,
        secret: str,
        *,
        transport: httpx.AsyncBaseTransport | None = None,
        timeout: float = 30.0,
    ):
        self._base = base_url.rstrip("/") + "/_matrix/provision"
        self._secret = secret
        self._transport = transport
        self._timeout = timeout

    async def _request(
        self,
        method: str,
        path: str,
        user_id: str,
        body: dict[str, Any] | None = None,
        timeout: float | None = None,
    ) -> dict[str, Any]:
        try:
            async with httpx.AsyncClient(
                transport=self._transport, timeout=timeout or self._timeout
            ) as http:
                resp = await http.request(
                    method,
                    self._base + path,
                    params={"user_id": user_id},
                    json=body if body is not None else ({} if method == "POST" else None),
                    headers={"Authorization": f"Bearer {self._secret}"},
                )
        except httpx.TimeoutException as exc:
            raise ProvisioningError(504, "TIMEOUT") from exc
        except httpx.HTTPError as exc:
            raise ProvisioningError(503, "UNAVAILABLE") from exc
        try:
            data = resp.json()
        except ValueError:
            data = {}
        if resp.status_code >= 400:
            raise ProvisioningError(
                resp.status_code, str(data.get("errcode", "UNKNOWN")), str(data.get("error", ""))
            )
        return data

    async def flows(self, user_id: str) -> list[dict[str, Any]]:
        return (await self._request("GET", "/v3/login/flows", user_id)).get("flows", [])

    async def start(self, user_id: str, flow_id: str) -> dict[str, Any]:
        return await self._request("POST", f"/v3/login/start/{flow_id}", user_id)

    async def step(
        self,
        user_id: str,
        process_id: str,
        step_id: str,
        step_type: str,
        body: dict[str, Any] | None = None,
        timeout: float | None = None,
    ) -> dict[str, Any]:
        path = f"/v3/login/step/{process_id}/{step_id}/{step_type}"
        return await self._request("POST", path, user_id, body, timeout)

    async def cancel(self, user_id: str, process_id: str) -> None:
        await self._request("POST", f"/v3/login/cancel/{process_id}", user_id)

    async def logins(self, user_id: str) -> list[str]:
        return (await self._request("GET", "/v3/logins", user_id)).get("login_ids", [])

    async def logout(self, user_id: str, login_id: str) -> None:
        await self._request("POST", f"/v3/logout/{login_id}", user_id)

    async def whoami(self, user_id: str) -> dict[str, Any]:
        return await self._request("GET", "/v3/whoami", user_id)
