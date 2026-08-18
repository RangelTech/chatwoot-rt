import pytest

pytestmark = pytest.mark.integration


def _tenant_com_usuario(tenant_id: str) -> None:
    from app.db import get_connection

    with get_connection() as conn:
        conn.execute(
            """INSERT INTO tenant_links (tenant_id, tenant_key, tenant_name, chatwoot_account_id)
               VALUES (%s, 'loja', 'Loja', 7)""",
            (tenant_id,),
        )
        conn.execute(
            """INSERT INTO user_links (tenant_id, platform_user_id, email, chatwoot_user_id, role)
               VALUES (%s, gen_random_uuid(), 'dono@loja.com', 3, 'administrator')""",
            (tenant_id,),
        )


def test_provision_tenant_registra_webhook_e_macro(
    client, admin_auth, tenant_id, monkeypatch
):
    from app.config import settings
    from app.services import chatwoot, tenants

    monkeypatch.setattr(settings, "bridge_public_url", "https://bridge.rangeltech.net")

    webhooks_criados = []
    macros_criadas = []

    async def falso_token(_user_id):
        return "token-de-conta"

    async def falso_create_team(account_id, token, name):
        return {"id": 900 if name == "Fila IA" else 901}

    async def falso_list_webhooks(account_id, token):
        return [{"url": url} for url, _ in webhooks_criados]

    async def falso_create_webhook(account_id, token, url, subscriptions):
        webhooks_criados.append((url, subscriptions))
        return {"id": 1}

    async def falso_list_macros(account_id, token):
        return [{"name": name} for name, _ in macros_criadas]

    async def falso_create_macro(account_id, token, name, actions, visibility="global"):
        macros_criadas.append((name, actions))
        return {"id": 1}

    monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
    monkeypatch.setattr(chatwoot, "create_team", falso_create_team)
    monkeypatch.setattr(chatwoot, "list_account_webhooks", falso_list_webhooks)
    monkeypatch.setattr(chatwoot, "create_account_webhook", falso_create_webhook)
    monkeypatch.setattr(chatwoot, "list_macros", falso_list_macros)
    monkeypatch.setattr(chatwoot, "create_macro", falso_create_macro)

    _tenant_com_usuario(tenant_id)

    resp = client.post(
        "/admin/tenants",
        headers=admin_auth,
        json={"tenant_id": tenant_id, "tenant_key": "loja", "tenant_name": "Loja"},
    )
    assert resp.status_code == 200

    assert len(webhooks_criados) == 1
    url, subscriptions = webhooks_criados[0]
    token = tenants.get_tenant_link(tenant_id)["conversation_webhook_token"]
    assert token
    assert url == f"https://bridge.rangeltech.net/agent-bot/label/{token}"
    assert subscriptions == ["conversation_updated"]

    assert len(macros_criadas) == 1
    name, actions = macros_criadas[0]
    assert name == "Devolver para IA"
    assert {"action_name": "add_label", "action_params": ["ia-retomar"]} in actions
    assert {"action_name": "assign_team", "action_params": [900]} in actions

    # Rodar de novo (retroativo) não duplica.
    resp2 = client.post(
        "/admin/tenants",
        headers=admin_auth,
        json={"tenant_id": tenant_id, "tenant_key": "loja", "tenant_name": "Loja"},
    )
    assert resp2.status_code == 200
    assert len(webhooks_criados) == 1
    assert len(macros_criadas) == 1


def test_label_webhook_devolve_conversa_para_ia_e_limpa_label(
    client, tenant_id, monkeypatch
):
    from app.services import chatwoot, tenants

    _tenant_com_usuario(tenant_id)
    token = tenants.ensure_conversation_webhook_token(tenant_id)
    tenants.set_conversation_state(
        tenant_id=tenant_id, conversation_id=555, state="human_active"
    )

    async def falso_token(_user_id):
        return "token-de-conta"

    async def falso_get_conversation(account_id, token, conversation_id):
        # display_id (42, o do payload) != id global (555, o usado no bridge).
        assert conversation_id == 42
        return {"id": 555}

    labels_atuais = ["ia-retomar", "vip"]
    labels_definidas = []

    async def falso_get_labels(account_id, token, conversation_id):
        return labels_atuais

    async def falso_set_labels(account_id, token, conversation_id, labels):
        labels_definidas.append(labels)
        return {}

    monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
    monkeypatch.setattr(chatwoot, "get_conversation", falso_get_conversation)
    monkeypatch.setattr(chatwoot, "get_conversation_labels", falso_get_labels)
    monkeypatch.setattr(chatwoot, "set_conversation_labels", falso_set_labels)

    resp = client.post(
        f"/agent-bot/label/{token}",
        json={
            "event": "conversation_updated",
            "id": 42,
            "labels": ["ia-retomar", "vip"],
        },
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "accepted"

    state = tenants.conversation_state(tenant_id, 555)
    assert state["state"] == "ai_active"
    assert labels_definidas == [["vip"]]


def test_label_webhook_ignora_sem_a_label_reservada(client, tenant_id):
    from app.services import tenants

    _tenant_com_usuario(tenant_id)
    token = tenants.ensure_conversation_webhook_token(tenant_id)
    tenants.set_conversation_state(
        tenant_id=tenant_id, conversation_id=555, state="human_active"
    )

    resp = client.post(
        f"/agent-bot/label/{token}",
        json={"event": "conversation_updated", "id": 42, "labels": ["vip"]},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "ignored"

    state = tenants.conversation_state(tenant_id, 555)
    assert state["state"] == "human_active"


def test_label_webhook_token_desconhecido(client):
    resp = client.post(
        "/agent-bot/label/token-que-nao-existe",
        json={"event": "conversation_updated", "id": 1, "labels": []},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "unknown_tenant"
