"""Gateway em modo simulador (QA/CDP): roteiros deterministicos de login e entrada simulada."""

import time

import pytest
from app.channels import api as channels_api
from app.config import settings

CONSENT = {"accepted": True, "version": "t"}


@pytest.fixture
def sim(_schema, monkeypatch):
    import psycopg
    from app.main import app
    from fastapi.testclient import TestClient

    monkeypatch.setattr(settings, "channels_gateway_token", "tok")
    monkeypatch.setattr(settings, "channels_simulator", True)
    monkeypatch.setattr(settings, "channels_sim_scan_after_s", 0.4)
    monkeypatch.setattr(settings, "channels_sim_approve_after_s", 0.4)
    monkeypatch.setattr(settings, "matrix_server_name", "test.local")
    with psycopg.connect(settings.database_url, autocommit=True) as c:
        c.execute("TRUNCATE rt_channel_connections CASCADE")
        c.execute("TRUNCATE rt_channel_audit, rt_channel_login_attempts")
    channels_api.set_gateway(None)
    with TestClient(app) as client:  # um unico loop: os workers sao subprocessos desse loop
        client.headers.update({"Authorization": "Bearer tok"})
        yield client
        gw = channels_api._gateway
        tk = gw.adapters.get("tiktok") if gw else None
        for p in list(tk._procs.values() if tk else []):
            client.portal.call(p.stop)
    channels_api.set_gateway(None)


def connect(c, provider, account=1):
    r = c.post(
        "/internal/channels/connections",
        json={"account_id": account, "provider": provider, "consent": CONSENT},
    )
    assert r.status_code == 201, r.text
    return r.json()


def step(c, cid, kind, data, account=1):
    return c.post(
        f"/internal/channels/connections/{cid}/step",
        json={"account_id": account, "step_id": "s", "kind": kind, "data": data},
    ).json()


def status(c, cid, account=1):
    return c.get(f"/internal/channels/connections/{cid}", params={"account_id": account}).json()


def test_catalogo_do_simulador_tem_os_quatro(sim):
    cat = sim.get("/internal/channels/catalog").json()
    assert {p["provider"] for p in cat["providers"]} == {
        "instagram",
        "messenger",
        "tiktok",
        "whatsapp",
    }


@pytest.mark.parametrize(
    ("password", "expect"),
    [("bad", "wrong_password"), ("locked", "account_locked")],
)
def test_instagram_erros(sim, password, expect):
    c = connect(sim, "instagram")
    r = step(
        sim,
        c["connection"]["id"] if "connection" in c else c["id"],
        "credentials",
        {"username": "qa", "password": password},
    )
    assert r["step"]["error_code"] == expect


def _cid(c):
    return c["connection"]["id"] if "connection" in c else c["id"]


def test_instagram_2fa_e_challenge(sim):
    c = connect(sim, "instagram")
    r = step(sim, _cid(c), "credentials", {"username": "qa", "password": "2fa"})
    assert r["step"]["kind"] == "code_2fa"
    r = step(sim, _cid(c), "code_2fa", {"verification_code": "000000"})
    assert r["step"]["error_code"] == "wrong_code"
    r = step(sim, _cid(c), "code_2fa", {"verification_code": "123456"})
    assert (
        r["connection"]["state"] == "connected" if "connection" in r else r["state"] == "connected"
    )

    c2 = connect(sim, "instagram")
    r = step(sim, _cid(c2), "credentials", {"username": "qa2", "password": "challenge"})
    assert r["step"]["kind"] == "await_approval"
    time.sleep(0.6)
    assert (
        status(sim, _cid(c2)).get("state", status(sim, _cid(c2)).get("connection", {}).get("state"))
        == "connected"
    )


def test_whatsapp_qr_renova_e_conecta(sim):
    c = connect(sim, "whatsapp")
    first = c["step"]["qr"]["data"]
    nxt = status(sim, _cid(c))
    assert nxt["step"]["kind"] == "qr"
    time.sleep(0.6)
    final = status(sim, _cid(c))
    assert (final.get("state") or final["connection"]["state"]) == "connected"
    assert first.startswith("https://wa.me/settings/linked_devices#sim-")


def test_tiktok_qr_auto_scan_e_entrada_simulada(sim):
    c = connect(sim, "tiktok")
    cid = _cid(c)
    assert c["step"]["kind"] == "qr"
    time.sleep(0.8)
    final = None
    for _ in range(20):
        final = status(sim, cid)
        if (final.get("state") or final["connection"]["state"]) == "connected":
            break
        time.sleep(0.3)
    assert (final.get("state") or final["connection"]["state"]) == "connected"
    sim.put(
        f"/internal/channels/connections/{cid}/delivery",
        json={
            "account_id": 1,
            "webhook_url": "http://rails/x",
            "webhook_secret": "s",
            "inbox_ref": "1",
        },
    )
    r = sim.post(
        "/internal/channels/sim/inbound",
        json={"account_id": 1, "connection_id": cid, "text": "ola simulado"},
    )
    assert r.status_code == 200 and r.json()["queued"] is True
    # outro tenant nao injeta na conexao alheia
    r = sim.post(
        "/internal/channels/sim/inbound",
        json={"account_id": 2, "connection_id": cid, "text": "invasor"},
    )
    assert r.status_code == 404


def test_sim_inbound_some_fora_do_simulador(sim, monkeypatch):
    c = connect(sim, "whatsapp")
    monkeypatch.setattr(settings, "channels_simulator", False)
    r = sim.post(
        "/internal/channels/sim/inbound",
        json={"account_id": 1, "connection_id": _cid(c)},
    )
    assert r.status_code == 404
