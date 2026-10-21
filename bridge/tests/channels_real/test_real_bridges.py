"""Contrato do adaptador contra os bridges mautrix REAIS (v26.10) do smoke local.

So roda com BRIDGE_SMOKE_DIR apontando para o diretorio de dados do smoke
(`stacks/canais/smoke-local/up.sh <dir>`), que tem o canais.env com o segredo de
provisionamento. Nenhuma conta real: so passos iniciais (sem enviar credencial).
"""

import os
import pathlib

import pytest
from app.channels.models import ConnectionCtx
from app.channels.providers.matrix_bridge import ALLOWED_FLOWS, MatrixBridgeAdapter
from app.channels.provisioning import ProvisioningClient, ProvisioningError

D = os.environ.get("BRIDGE_SMOKE_DIR")
pytestmark = pytest.mark.skipif(not D, reason="BRIDGE_SMOKE_DIR nao definido")

PORTS = {"messenger": 29391, "instagram": 29392, "whatsapp": 29393}


def _secret() -> str:
    for line in pathlib.Path(D, "canais.env").read_text().splitlines():
        if line.startswith("BRIDGE_PROVISIONING_SECRET="):
            return line.split("=", 1)[1]
    raise AssertionError("sem segredo")


def _client(provider: str, secret: str | None = None) -> ProvisioningClient:
    return ProvisioningClient(f"http://127.0.0.1:{PORTS[provider]}", secret or _secret())


def _ctx(provider: str, n: int = 1) -> ConnectionCtx:
    return ConnectionCtx(
        id=f"c{n}", account_id=n, provider=provider, matrix_user=f"@luar_t{n}_c{n}:matrix.internal"
    )


USER = "@luar_t1_c1:matrix.internal"


@pytest.mark.parametrize("provider", list(PORTS))
async def test_fluxos_permitidos_existem_e_cookie_nao_e_usado(provider):
    flows = {f["id"] for f in await _client(provider).flows(USER)}
    assert ALLOWED_FLOWS[provider] <= flows, flows
    adapter_default = {"instagram": "android", "messenger": "messenger-lite", "whatsapp": "qr"}
    assert adapter_default[provider] in flows


@pytest.mark.parametrize("provider", list(PORTS))
async def test_sem_segredo_ou_usuario_de_outro_dominio_e_recusado(provider):
    with pytest.raises(ProvisioningError) as e:
        await _client(provider, "x" * 20).flows(USER)
    assert e.value.status == 401
    with pytest.raises(ProvisioningError) as e:
        await _client(provider).flows("@invasor:evil.org")
    assert e.value.errcode == "M_FORBIDDEN"


@pytest.mark.parametrize(
    ("provider", "flow", "step_id"),
    [
        ("instagram", "android", "fi.mau.meta.instagram.credentials"),
        ("messenger", "messenger-lite", "fi.mau.meta.messengerlite.email_password"),
        ("messenger", "messenger-lite-android", "fi.mau.meta.messengerlite.email_password"),
    ],
)
async def test_login_por_senha_primeiro_passo(provider, flow, step_id):
    a = MatrixBridgeAdapter(provider, _client(provider))
    conn = _ctx(provider)
    view = await a.start_login(conn, flow)
    try:
        assert view.step.kind == "credentials"
        assert view.step.step_id == step_id
        fields = {f.id: f for f in view.step.fields}
        assert fields["password"].secret and fields["password"].type == "password"
        assert fields["username"].type == "username"
    finally:
        await a.cancel_login(conn)


async def test_whatsapp_qr_e_pareamento_por_telefone():
    a = MatrixBridgeAdapter("whatsapp", _client("whatsapp"))
    conn = _ctx("whatsapp")
    view = await a.start_login(conn, "qr")
    try:
        assert view.step.kind == "qr"
        assert view.step.qr.data.startswith("https://wa.me/settings/linked_devices#")
    finally:
        await a.cancel_login(conn)
    conn2 = _ctx("whatsapp", 2)
    view2 = await a.start_login(conn2, "phone")
    try:
        assert view2.step.kind == "credentials"
        assert [f.id for f in view2.step.fields] == ["phone_number"]
    finally:
        await a.cancel_login(conn2)


async def test_fluxo_de_cookie_recusado_pelo_adaptador():
    from app.channels.providers.base import ProviderError

    a = MatrixBridgeAdapter("instagram", _client("instagram"))
    for flow in ("instagram", "instagram-password"):
        with pytest.raises(ProviderError) as e:
            await a.start_login(_ctx("instagram"), flow)
        assert e.value.error_code == "unsupported_step"
