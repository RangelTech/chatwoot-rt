import httpx
import psycopg
import pytest
from app.channels import api as channels_api
from app.channels.providers.base import ProviderError
from app.channels.providers.matrix_bridge import MatrixBridgeAdapter
from app.channels.provisioning import ProvisioningClient
from app.channels.service import Gateway
from tests.channels.fake_bridge import SECRET, FakeBridge

TOKEN = "gw-token-teste"


class FakeSender:
    def __init__(self):
        self.sent: list[tuple] = []
        self.fail: str | None = None
        self.n = 0

    async def __call__(self, conn, conversation_ref, text, attachments, reply_to):
        if self.fail:
            raise ProviderError(self.fail)
        self.n += 1
        self.sent.append((conn.id, conversation_ref, text))
        return f"$ev{self.n}"


class Env:
    def __init__(self, bridge, sender, gw, posted, status):
        self.bridge, self.sender, self.gw, self.posted, self.status = (
            bridge,
            sender,
            gw,
            posted,
            status,
        )


@pytest.fixture
def env(_schema, monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, "channels_gateway_token", TOKEN)
    monkeypatch.setattr(settings, "matrix_hs_token", "hs-token-teste")
    monkeypatch.setattr(settings, "matrix_server_name", "test.local")
    with psycopg.connect(settings.database_url, autocommit=True) as c:
        c.execute("TRUNCATE rt_channel_connections CASCADE")
        c.execute(
            "TRUNCATE rt_channel_audit, rt_channel_login_attempts, rt_channel_appservice_txns"
        )
    bridge = FakeBridge()
    sender = FakeSender()
    posted: list[httpx.Request] = []
    status = {"code": 200}

    def hook(req):
        posted.append(req)
        return httpx.Response(status["code"])

    http = httpx.AsyncClient(transport=httpx.MockTransport(hook))
    adapters = {
        p: MatrixBridgeAdapter(
            p, ProvisioningClient("http://bridge", SECRET, transport=bridge.transport()), sender
        )
        for p in ("instagram", "messenger", "whatsapp")
    }
    gw = Gateway(adapters, http=http)
    channels_api.set_gateway(gw)
    yield Env(bridge, sender, gw, posted, status)
    channels_api.set_gateway(None)


@pytest.fixture
def api(env):
    from app.main import app
    from fastapi.testclient import TestClient

    c = TestClient(app)
    c.headers.update({"Authorization": f"Bearer {TOKEN}"})
    return c
