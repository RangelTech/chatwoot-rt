"""Contratos da ponte: isolamento, idempotência e máquina de estados."""

import pytest

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

