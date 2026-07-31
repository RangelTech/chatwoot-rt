"""Contratos da ponte: isolamento, idempotência e máquina de estados."""

import json
import uuid

import psycopg
import pytest
from app.config import settings
from app.providers import wapi

pytestmark = pytest.mark.integration


def _link_tenant(tenant_id: str, account_id: int = 1) -> None:
    from app.services import tenants

    tenants.upsert_tenant_link(tenant_id=tenant_id, tenant_key="t", tenant_name="Tenant")
    tenants.set_chatwoot_account(tenant_id, account_id)


def test_admin_routes_require_the_shared_token(client, tenant_id):
    r = client.post(
        "/admin/tenants",
        json={"tenant_id": tenant_id, "tenant_key": "t", "tenant_name": "T"},
    )
    assert r.status_code == 401


def test_extract_message_ignores_status_events_and_echo():
    status_event = {"event": "message.status", "phone": "5511999", "text": "oi"}
    assert wapi.extract_message(status_event) is None
    assert wapi.extract_message({"fromMe": True, "phone": "5511999", "text": "oi"}) is None
    assert wapi.extract_message({"phone": "5511999@c.us", "text": "  "}) is None

    message = wapi.extract_message({"phone": "5511999@c.us", "text": "olá", "messageId": "m1"})
    assert message == {
        "provider": "wapi",
        "contact": "5511999",
        "text": "olá",
        "external_id": "m1",
        "contact_name": "5511999",
    }


def test_channel_credentials_are_encrypted_at_rest(client, tenant_id):
    from app.services import tenants

    _link_tenant(tenant_id)
    secret = f"tok-{uuid.uuid4().hex}"
    channel = tenants.upsert_channel(
        tenant_id=tenant_id,
        provider="wapi",
        external_id=f"inst-{uuid.uuid4().hex[:6]}",
        credentials={"token": secret},
        api_base="https://api.w-api.app/v1",
    )
    assert secret not in json.dumps(dict(channel), default=str)
    assert tenants.channel_credentials(channel)["token"] == secret

    with psycopg.connect(settings.database_url) as conn:
        stored = conn.execute("SELECT credentials_encrypted FROM tenant_channels").fetchall()
    assert stored and all(secret not in (s[0] or "") for s in stored)


def test_a_channel_cannot_be_stolen_by_another_tenant(client, tenant_id):
    from app.services import tenants

    _link_tenant(tenant_id)
    other = str(uuid.uuid4())
    _link_tenant(other, account_id=2)
    external_id = f"inst-{uuid.uuid4().hex[:6]}"
    tenants.upsert_channel(
        tenant_id=tenant_id, provider="wapi", external_id=external_id,
        credentials={"token": "a"}, api_base="https://x",
    )
    with pytest.raises(PermissionError):
        tenants.upsert_channel(
            tenant_id=other, provider="wapi", external_id=external_id,
            credentials={"token": "b"}, api_base="https://x",
        )


def test_unknown_webhook_never_lands_in_a_tenant(client):
    r = client.post("/webhooks/wapi/nao-existe", json={"phone": "5511999", "text": "oi"})
    assert r.status_code == 200
    assert r.json()["status"] == "ignored"

    with psycopg.connect(settings.database_url) as conn:
        row = conn.execute(
            "SELECT tenant_id, state FROM channel_events ORDER BY created_at DESC LIMIT 1"
        ).fetchone()
    assert row[0] is None and row[1] == "unknown_channel"


def test_repeated_delivery_is_ignored_once(client, tenant_id):
    """Provedor reenvia o mesmo evento: a conversa não pode duplicar."""
    from app.services import tenants

    _link_tenant(tenant_id)
    channel = tenants.upsert_channel(
        tenant_id=tenant_id, provider="wapi", external_id=f"inst-{uuid.uuid4().hex[:6]}",
        credentials={"token": "a"}, api_base="https://x",
    )
    body = {"phone": "5511988887777", "text": "quero um lanche", "messageId": "msg-1"}
    path = f"/webhooks/wapi/{channel['webhook_token']}"

    first = client.post(path, json=body)
    second = client.post(path, json=body)
    assert first.json()["status"] == "accepted"
    assert second.json()["status"] == "duplicate_ignored"


def test_malformed_body_is_recorded_and_answered_with_200(client, tenant_id):
    from app.services import tenants

    _link_tenant(tenant_id)
    channel = tenants.upsert_channel(
        tenant_id=tenant_id, provider="wapi", external_id=f"inst-{uuid.uuid4().hex[:6]}",
        credentials={"token": "a"}, api_base="https://x",
    )
    r = client.post(
        f"/webhooks/wapi/{channel['webhook_token']}",
        content=b"nao-e-json",
        headers={"Content-Type": "application/json"},
    )
    assert r.status_code == 200

    with psycopg.connect(settings.database_url) as conn:
        row = conn.execute(
            "SELECT state, raw_body FROM channel_events ORDER BY created_at DESC LIMIT 1"
        ).fetchone()
    assert row[0] == "unparseable" and "nao-e-json" in row[1]


def test_a_human_reply_takes_the_conversation_from_the_ai(client, tenant_id):
    """Enquanto o humano estiver no comando, o bot não responde por cima."""
    from app.services import tenants

    _link_tenant(tenant_id, account_id=77)
    tenants.set_conversation_state(
        tenant_id=tenant_id, conversation_id=5, state="ai_active", session_id="s1"
    )

    r = client.post(
        "/agent-bot",
        json={
            "event": "message_created",
            "account": {"id": 77},
            "message_type": "outgoing",
            "private": False,
            "sender": {"type": "user"},
            "conversation": {"id": 5},
            "content": "oi, sou a atendente",
        },
    )
    assert r.status_code == 200
    assert tenants.conversation_state(tenant_id, 5)["state"] == "human_active"


def test_agent_bot_ignores_events_from_unknown_accounts(client):
    r = client.post(
        "/agent-bot",
        json={"event": "message_created", "account": {"id": 999999}, "message_type": "incoming"},
    )
    assert r.json()["status"] == "unknown_account"


def test_private_notes_do_not_go_back_to_the_channel(client, tenant_id):
    from app.services import tenants

    _link_tenant(tenant_id)
    channel = tenants.upsert_channel(
        tenant_id=tenant_id, provider="wapi", external_id=f"inst-{uuid.uuid4().hex[:6]}",
        credentials={"token": "a"}, api_base="https://x",
    )
    r = client.post(
        f"/outbound/{channel['webhook_token']}",
        json={
            "message_type": "outgoing",
            "private": True,
            "content": "nota interna",
            "conversation": {"meta": {"sender": {"identifier": "5511999"}}},
        },
    )
    assert r.json()["status"] == "ignored"
