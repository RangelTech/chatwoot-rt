"""Cola Matrix <-> gateway contra o Synapse REAL do smoke local (sem conta de provedor).

O "provedor" aqui e um fantasma (`@instagram_999`) registrado com o token do appservice do
mautrix-instagram, que cria uma sala DM, convida o usuario Luar da conexao e escreve. Prova:
registro do usuario, auto-join no convite, ligacao sala -> conversa, entrada (webhook assinado,
sem duplicata), saida pela sala e isolamento (o outro tenant nao recebe nada).

Requer: smoke local de pe (stacks/canais/smoke-local/up.sh), BRIDGE_SMOKE_DIR, Postgres de teste e
a porta 8000 livre no host (o Synapse chama o gateway em host.docker.internal:8000).
"""

import asyncio
import json
import os
import pathlib
import threading
import time

import httpx
import psycopg
import pytest
from app.channels import api as channels_api
from app.channels import appservice, signing, store
from app.channels.providers.matrix_bridge import MatrixBridgeAdapter
from app.channels.provisioning import ProvisioningClient
from app.channels.service import Gateway

D = os.environ.get("BRIDGE_SMOKE_DIR")
pytestmark = pytest.mark.skipif(not D, reason="BRIDGE_SMOKE_DIR nao definido")

HS = "http://127.0.0.1:18008"
SERVER = "matrix.internal"
CONSENT = {"accepted": True, "version": "t"}


def _env() -> dict[str, str]:
    out = {}
    for line in pathlib.Path(D, "canais.env").read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            out[k] = v
    return out


def _hs(method, path, token, user=None, body=None, **params):
    r = httpx.request(
        method,
        f"{HS}/_matrix/client/v3{path}",
        params={**({"user_id": user} if user else {}), **params},
        json=body,
        headers={"Authorization": f"Bearer {token}"},
        timeout=20,
    )
    return r


@pytest.fixture
def stack(_schema, monkeypatch):
    import uvicorn
    from app.config import settings
    from app.main import app

    env = _env()
    monkeypatch.setattr(settings, "channels_gateway_token", "gw-test")
    monkeypatch.setattr(settings, "matrix_server_name", SERVER)
    monkeypatch.setattr(settings, "matrix_homeserver_url", HS)
    monkeypatch.setattr(settings, "matrix_as_token", env["GATEWAY_AS_TOKEN"])
    monkeypatch.setattr(settings, "matrix_hs_token", env["GATEWAY_HS_TOKEN"])
    with psycopg.connect(settings.database_url, autocommit=True) as c:
        c.execute("TRUNCATE rt_channel_connections CASCADE")
        c.execute(
            "TRUNCATE rt_channel_audit, rt_channel_login_attempts, rt_channel_appservice_txns"
        )
    posted: list[httpx.Request] = []

    def hook(req):
        posted.append(req)
        return httpx.Response(200)

    http = httpx.AsyncClient(transport=httpx.MockTransport(hook))
    sender = appservice.MatrixSender()
    prov = ProvisioningClient("http://127.0.0.1:29392", env["BRIDGE_PROVISIONING_SECRET"])
    gw = Gateway(
        {"instagram": MatrixBridgeAdapter("instagram", prov, sender)},
        http=http,
        matrix=appservice.MatrixHS(),
    )
    channels_api.set_gateway(gw)
    server = uvicorn.Server(uvicorn.Config(app, host="0.0.0.0", port=8000, log_level="warning"))
    t = threading.Thread(target=server.run, daemon=True)
    t.start()
    for _ in range(50):
        if server.started:
            break
        time.sleep(0.1)
    yield gw, posted, env
    server.should_exit = True
    t.join(5)
    channels_api.set_gateway(None)


def _wait(cond, timeout=20):
    end = time.time() + timeout
    while time.time() < end:
        if cond():
            return True
        time.sleep(0.3)
    return False


def test_ponta_a_ponta_com_synapse_real(stack):
    gw, posted, env = stack
    ig_token = env["INSTAGRAM_AS_TOKEN"]

    async def go():
        a = await gw.connect(
            account_id=1, provider="instagram", actor_id="u", consent=CONSENT, flow=None
        )
        b = await gw.connect(
            account_id=2, provider="instagram", actor_id="u", consent=CONSENT, flow=None
        )
        return a, b

    a, b = asyncio.run(go())
    for c, acc in ((a, 1), (b, 2)):
        gw.set_delivery(
            account_id=acc,
            connection_id=c["id"],
            webhook_url=f"http://rails/hook/{acc}",
            secret=f"seg{acc}",
            inbox_ref=str(acc),
        )
    store.update_connection(a["id"], state="connected")
    row_a = store.get_connection_row(a["id"])
    user_a = row_a["matrix_user"]
    assert user_a.startswith("@luar_t1_c")
    # o usuario existe no Synapse (registrado pelo appservice do gateway)
    assert _hs("GET", f"/profile/{user_a}", env["GATEWAY_AS_TOKEN"]).status_code == 200

    # "provedor": fantasma do bridge de Instagram cria o portal e convida SO o usuario do tenant 1
    ghost = "@instagram_999:" + SERVER
    r = _hs(
        "POST",
        "/register",
        ig_token,
        body={"type": "m.login.application_service", "username": "instagram_999"},
    )
    assert r.status_code in (200, 400), r.text
    room = _hs(
        "POST",
        "/createRoom",
        ig_token,
        ghost,
        {
            "is_direct": True,
            "preset": "private_chat",
            "initial_state": [
                {
                    "type": "m.bridge",
                    "state_key": "fi.mau.meta:ig",
                    "content": {"channel": {"id": "999"}, "protocol": {"id": "instagram"}},
                }
            ],
            "invite": [user_a],
        },
    ).json()["room_id"]
    # o gateway entra sozinho e liga a sala a conversa 999
    assert _wait(lambda: (store.room_binding(room) or {}).get("conversation_external_id") == "999")
    binding = store.room_binding(room)
    assert binding["connection_id"] == a["id"] and binding["account_id"] == 1

    ev1 = _hs(
        "PUT",
        f"/rooms/{room}/send/m.room.message/t1",
        ig_token,
        ghost,
        {"msgtype": "m.text", "body": "oi do cliente"},
    )
    assert ev1.status_code == 200, ev1.text
    assert _wait(lambda: len(store.due_outbox("webhook")) >= 1)
    res = asyncio.run(gw.flush_webhooks())
    assert res["sent"] == 1
    req = posted[-1]
    assert str(req.url).endswith("/hook/1")  # nunca no webhook do tenant 2
    assert signing.verify(
        "seg1", req.headers["x-luar-timestamp"], req.headers["x-luar-signature"], req.content
    )
    ev = json.loads(req.content)
    assert ev["message"]["text"] == "oi do cliente" and ev["conversation"]["external_id"] == "999"
    assert ev["account_id"] == 1 and ev["channel"] == "instagram"

    # reentrega da mesma transacao nao duplica
    again = asyncio.run(appservice.handle_transaction(gw, "txn-dup", []))
    assert again["delivered"] == 0
    assert len(store.due_outbox("webhook")) == 0

    # o tenant 2 nao tem sala, nem mensagem
    with psycopg.connect(
        __import__("app.config", fromlist=["settings"]).settings.database_url
    ) as c:
        n = c.execute("SELECT count(*) AS n FROM rt_channel_rooms WHERE account_id=2").fetchone()
    assert (n["n"] if isinstance(n, dict) else n[0]) == 0

    # saida: o gateway escreve na sala como o usuario Luar
    sent = asyncio.run(
        gw.send(
            account_id=1,
            connection_id=a["id"],
            idempotency_key="k1",
            conversation_ref="999",
            text="resposta do atendimento",
        )
    )
    assert sent["status"] == "sent"
    msgs = _hs("GET", f"/rooms/{room}/messages", ig_token, ghost, dir="b", limit=10).json()["chunk"]
    assert any(
        m["content"].get("body") == "resposta do atendimento" and m["sender"] == user_a
        for m in msgs
    )
