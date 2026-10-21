"""Gateway de canais contra o bridge falso: login, estados, isolamento, envio, entrada."""

import json

import pytest
from app.channels import appservice, signing, store
from app.channels.models import InboundMessage
from app.channels.states import State, can_transition

CONSENT = {"accepted": True, "version": "2026-10-20"}


def connect(api, account=1, provider="instagram", **kw):
    r = api.post(
        "/internal/channels/connections",
        json={
            "account_id": account,
            "provider": provider,
            "actor_id": "u1",
            "consent": CONSENT,
            **kw,
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def step(api, cid, kind, data, account=1, step_id="s"):
    r = api.post(
        f"/internal/channels/connections/{cid}/step",
        json={"account_id": account, "step_id": step_id, "kind": kind, "data": data},
    )
    return r


def test_auth_obrigatoria(env, api):
    r = api.get("/internal/channels/catalog", headers={"Authorization": "Bearer x"})
    assert r.status_code == 401


def test_catalogo_so_experimental_sem_cookie(env, api):
    cat = api.get("/internal/channels/catalog").json()
    assert {p["provider"] for p in cat["providers"]} == {
        "instagram",
        "messenger",
        "tiktok",
        "whatsapp",
    }
    assert "cookie" not in json.dumps(cat).lower()


def test_consentimento_obrigatorio(env, api):
    r = api.post(
        "/internal/channels/connections",
        json={"account_id": 1, "provider": "instagram", "consent": {"accepted": False}},
    )
    assert r.status_code == 400 and r.json()["detail"] == "consent_required"


def test_instagram_login_ok(env, api):
    c = connect(api)
    assert c["state"] == "pending_auth" and c["step"]["kind"] == "credentials"
    assert [f["type"] for f in c["step"]["fields"]] == ["username", "password"]
    assert c["step"]["fields"][1]["secret"] is True
    r = step(api, c["id"], "credentials", {"username": "ana", "password": "ok"})
    assert r.json()["state"] == "connected"
    aud = [a["action"] for a in store.audit_list(c["id"])]
    assert aud == ["connect_started", "connected"]


def test_login_2fa(env, api):
    c = connect(api)
    r = step(api, c["id"], "credentials", {"username": "ana", "password": "2fa"}).json()
    assert r["state"] == "awaiting_2fa" and r["step"]["kind"] == "code_2fa"
    bad = step(api, c["id"], "code_2fa", {"verification_code": "000000"}).json()
    assert bad["step"]["error_code"] == "wrong_code"
    ok = step(api, c["id"], "code_2fa", {"verification_code": "123456"}).json()
    assert ok["state"] == "connected"


def test_senha_errada_e_conta_bloqueada(env, api):
    c = connect(api)
    r = step(api, c["id"], "credentials", {"username": "ana", "password": "bad"}).json()
    assert r["step"]["error_code"] == "wrong_password" and r["step"]["attempts_left"] == 4
    assert r["state"] == "pending_auth"
    r = step(api, c["id"], "credentials", {"username": "ana", "password": "locked"}).json()
    assert r["step"]["error_code"] == "account_locked"


def test_limite_de_tentativas(env, api):
    c = connect(api)
    for _ in range(5):
        step(api, c["id"], "credentials", {"username": "ana", "password": "bad"})
    r = step(api, c["id"], "credentials", {"username": "ana", "password": "ok"})
    assert r.status_code == 429 and r.json()["detail"] == "too_many_attempts"
    # outro identificador no mesmo tenant ainda pode tentar (limite por conta externa)
    assert (
        step(api, c["id"], "credentials", {"username": "bia", "password": "ok"}).status_code == 200
    )


def test_verificacao_aguarda_aprovacao(env, api):
    c = connect(api)
    r = step(api, c["id"], "credentials", {"username": "ana", "password": "challenge"}).json()
    assert r["state"] == "awaiting_challenge" and r["step"]["kind"] == "await_approval"
    assert api.get(f"/internal/channels/connections/{c['id']}?account_id=1").json()["state"] == (
        "awaiting_challenge"
    )
    env.bridge.approve = True
    done = api.get(f"/internal/channels/connections/{c['id']}?account_id=1").json()
    assert done["state"] == "connected"


def test_qr_renova_e_conecta(env, api):
    c = connect(api, provider="whatsapp")
    assert c["step"]["kind"] == "qr" and c["step"]["qr"]["data"] == "2@qr-1"
    # polling sem leitura: bridge devolve novo QR
    r = api.get(f"/internal/channels/connections/{c['id']}?account_id=1").json()
    assert r["step"]["qr"]["data"] == "2@qr-2"
    env.bridge.qr_scanned = True
    r = api.get(f"/internal/channels/connections/{c['id']}?account_id=1").json()
    assert r["state"] == "connected"


def test_fluxo_de_cookie_e_webview_recusado(env, api):
    r = api.post(
        "/internal/channels/connections",
        json={
            "account_id": 1,
            "provider": "instagram",
            "consent": CONSENT,
            "login_flow": "instagram-password",
        },
    ).json()
    assert r["state"] == "disconnected" and r["step"]["error_code"] == "unsupported_step"
    assert all("instagram-password" not in p and "cookies" not in p for _, p in env.bridge.calls)


def test_isolamento_entre_tenants(env, api):
    c = connect(api, account=1)
    other = {"account_id": 2}
    assert api.get(f"/internal/channels/connections/{c['id']}", params=other).status_code == 404
    assert (
        step(
            api, c["id"], "credentials", {"username": "x", "password": "ok"}, account=2
        ).status_code
        == 404
    )
    for action in ("cancel", "disconnect", "revoke", "reauth"):
        r = api.post(f"/internal/channels/connections/{c['id']}/{action}", json=other)
        assert r.status_code == 404, action
    r = api.put(
        f"/internal/channels/connections/{c['id']}/delivery",
        json={**other, "webhook_url": "http://x", "webhook_secret": "s"},
    )
    assert r.status_code == 404
    assert api.get("/internal/channels/connections", params=other).json()["connections"] == []


def test_usuario_matrix_por_conexao_e_bridge_recusa_fora_do_padrao(env, api):
    c1, c2 = connect(api, account=1), connect(api, account=1)
    r1 = store.get_connection_row(c1["id"])
    r2 = store.get_connection_row(c2["id"])
    assert r1["matrix_user"] != r2["matrix_user"]
    assert r1["matrix_user"].startswith("@luar_t1_c") and r1["matrix_user"].endswith(":test.local")
    # bridge falso recusa usuario fora do padrao @luar_
    import asyncio

    from app.channels.provisioning import ProvisioningClient, ProvisioningError
    from tests.channels.fake_bridge import SECRET

    cli = ProvisioningClient("http://b", SECRET, transport=env.bridge.transport())
    with pytest.raises(ProvisioningError) as e:
        asyncio.run(cli.start("@alguem:test.local", "android"))
    assert e.value.status == 403


def test_disconnect_revoke_e_reauth(env, api):
    c = connect(api)
    step(api, c["id"], "credentials", {"username": "ana", "password": "ok"})
    assert store.get_connection_row(c["id"])["gateway_login_id"]
    r = api.post(f"/internal/channels/connections/{c['id']}/disconnect", json={"account_id": 1})
    assert r.json()["state"] == "disconnected"
    r = api.post(f"/internal/channels/connections/{c['id']}/revoke", json={"account_id": 1})
    assert r.json()["state"] == "revoked"
    assert (
        api.post(
            f"/internal/channels/connections/{c['id']}/reauth", json={"account_id": 1}
        ).status_code
        == 409
    )  # revogada nao volta


def test_reauth_apos_sessao_invalida_e_envio_pausado(env, api):
    c = connect(api)
    step(api, c["id"], "credentials", {"username": "ana", "password": "ok"})
    import asyncio

    asyncio.run(env.gw.on_session_invalid(c["id"], "session_invalid"))
    assert store.get_connection_row(c["id"])["state"] == "reauth_required"
    r = api.post(
        f"/internal/channels/connections/{c['id']}/send",
        json={"account_id": 1, "idempotency_key": "k", "conversation_ref": "t1", "text": "oi"},
    )
    assert r.status_code == 409 and r.json()["detail"] == "not_connected"
    r = api.post(f"/internal/channels/connections/{c['id']}/reauth", json={"account_id": 1})
    assert r.json()["state"] == "pending_auth" and r.json()["step"]["kind"] == "credentials"


def test_transicoes():
    assert can_transition(State.CONNECTED, State.DEGRADED)
    assert not can_transition(State.REVOKED, State.CONNECTED)
    assert not can_transition(State.CONNECTED, State.PENDING_AUTH)


# --- saida ---------------------------------------------------------------------


def _connected(api, env):
    c = connect(api)
    step(api, c["id"], "credentials", {"username": "ana", "password": "ok"})
    store.bind_room(
        room_id="!r1:test.local", connection_id=c["id"], account_id=1, conversation="t1"
    )
    return c


def test_envio_idempotente_sem_duplicar(env, api):
    c = _connected(api, env)
    body = {"account_id": 1, "idempotency_key": "msg-9", "conversation_ref": "t1", "text": "oi"}
    r1 = api.post(f"/internal/channels/connections/{c['id']}/send", json=body).json()
    r2 = api.post(f"/internal/channels/connections/{c['id']}/send", json=body).json()
    assert r1["status"] == r2["status"] == "sent" and r1["external_id"] == r2["external_id"]
    assert len(env.sender.sent) == 1


def test_envio_falha_vai_para_retry_e_depois_dead_letter(env, api, monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, "channels_webhook_max_attempts", 2)
    c = _connected(api, env)
    env.sender.fail = "provider_unavailable"
    body = {"account_id": 1, "idempotency_key": "m1", "conversation_ref": "t1", "text": "oi"}
    assert (
        api.post(f"/internal/channels/connections/{c['id']}/send", json=body).json()["status"]
        == "failed"
    )
    # mesma chave reenviada: nao cria linha nova
    assert (
        api.post(f"/internal/channels/connections/{c['id']}/send", json=body).json()["status"]
        == "dead"
    )
    assert (
        len(api.get("/internal/channels/dead-letters", params={"account_id": 1}).json()["items"])
        == 1
    )
    env.sender.fail = None


# --- entrada + webhook assinado ---------------------------------------------------


def _msg(cid, ext="$e1", conv="t1", direction="incoming"):
    from datetime import UTC, datetime

    return InboundMessage(
        connection_id=cid,
        conversation_external_id=conv,
        contact_external_id="@ghost:x",
        contact_name="Cli",
        message_external_id=ext,
        direction=direction,
        text="ola",
        sent_at=datetime.now(UTC),
    )


def test_entrada_dedup_e_webhook_assinado(env, api):
    import asyncio

    c = _connected(api, env)
    api.put(
        f"/internal/channels/connections/{c['id']}/delivery",
        json={
            "account_id": 1,
            "webhook_url": "http://rails/webhooks/channels/instagram_unofficial/7",
            "webhook_secret": "segredo-webhook",
            "inbox_ref": "7",
        },
    )
    assert asyncio.run(env.gw.inbound(_msg(c["id"]))) is True
    assert asyncio.run(env.gw.inbound(_msg(c["id"]))) is False  # duplicata
    res = api.post("/internal/channels/worker/flush").json()
    assert res["sent"] == 1 and len(env.posted) == 1
    req = env.posted[0]
    assert signing.verify(
        "segredo-webhook",
        req.headers["x-luar-timestamp"],
        req.headers["x-luar-signature"],
        req.content,
    )
    ev = json.loads(req.content)
    assert ev["message"]["external_id"] == "$e1" and ev["channel"] == "instagram"
    assert "password" not in req.content.decode().lower()


def test_webhook_falha_reenvia_e_replay_nao_valida(env, api):
    import asyncio

    c = _connected(api, env)
    api.put(
        f"/internal/channels/connections/{c['id']}/delivery",
        json={"account_id": 1, "webhook_url": "http://rails/x", "webhook_secret": "s3"},
    )
    asyncio.run(env.gw.inbound(_msg(c["id"], "$a")))
    env.status["code"] = 500
    assert api.post("/internal/channels/worker/flush").json()["failed"] == 1
    env.status["code"] = 200
    store_due = store.due_outbox("webhook")
    assert store_due == []  # backoff ainda nao venceu
    body = b"{}"
    assert not signing.verify("s3", "1", "sha256=00", body)
    old = signing.headers("s3", "e", body, now=1000)
    assert not signing.verify(
        "s3", old["X-Luar-Timestamp"], old["X-Luar-Signature"], body, now=5000
    )


def test_eco_de_envio_nao_duplica(env, api):
    import asyncio

    c = _connected(api, env)
    api.post(
        f"/internal/channels/connections/{c['id']}/send",
        json={"account_id": 1, "idempotency_key": "k1", "conversation_ref": "t1", "text": "x"},
    )
    # o provedor devolve o proprio evento enviado ($ev1) => nao gera webhook
    assert asyncio.run(env.gw.inbound(_msg(c["id"], "$ev1", direction="outgoing_echo"))) is False


def test_conexao_desconectada_ignora_entrada(env, api):
    import asyncio

    c = _connected(api, env)
    api.post(f"/internal/channels/connections/{c['id']}/disconnect", json={"account_id": 1})
    assert asyncio.run(env.gw.inbound(_msg(c["id"]))) is False


# --- appservice --------------------------------------------------------------------


def test_appservice_transacao_idempotente_e_sala_de_outro_tenant_ignorada(env, api):
    c = _connected(api, env)
    ev = {
        "type": "m.room.message",
        "room_id": "!r1:test.local",
        "event_id": "$m1",
        "sender": "@ghost_1:test.local",
        "origin_server_ts": 1760000000000,
        "content": {"msgtype": "m.text", "body": "oi"},
    }
    desconhecida = {**ev, "room_id": "!outra:test.local", "event_id": "$m2"}
    r = api.put(
        "/_matrix/app/v1/transactions/tx1?access_token=hs-token-teste",
        json={"events": [ev, desconhecida]},
        headers={},
    )
    assert r.status_code == 200 and r.json()["delivered"] == 1
    again = api.put(
        "/_matrix/app/v1/transactions/tx1?access_token=hs-token-teste", json={"events": [ev]}
    )
    assert again.json()["duplicate"] is True
    assert (
        api.put(
            "/_matrix/app/v1/transactions/tx2?access_token=errado", json={"events": []}
        ).status_code
        == 403
    )
    assert appservice.verify_hs_token("hs-token-teste")


def test_nenhum_segredo_no_banco_auditoria_ou_respostas(env, api):
    c = connect(api)
    r = step(api, c["id"], "credentials", {"username": "ana", "password": "SenhaSuperSecreta1"})
    assert "SenhaSuperSecreta1" not in r.text
    import psycopg
    from app.config import settings

    with psycopg.connect(settings.database_url) as conn:
        dump = ""
        for t in (
            "rt_channel_connections",
            "rt_channel_audit",
            "rt_channel_outbox",
            "rt_channel_login_attempts",
            "rt_channel_rooms",
            "rt_channel_messages",
        ):
            dump += str(conn.execute(f"SELECT * FROM {t}").fetchall())
    assert "SenhaSuperSecreta1" not in dump
    assert "ana" not in str(store.count_login_attempts) and "'ana'" not in dump
