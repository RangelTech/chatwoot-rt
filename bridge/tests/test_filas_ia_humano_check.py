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


def test_provision_tenant_cria_os_dois_teams(client, admin_auth, tenant_id, monkeypatch):
    from app.services import chatwoot

    criados = []

    async def falso_token(_user_id):
        return "token-de-conta"

    async def falso_create_team(account_id, token, name):
        criados.append((account_id, name))
        return {"id": 100 + len(criados)}

    monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
    monkeypatch.setattr(chatwoot, "create_team", falso_create_team)

    _tenant_com_usuario(tenant_id)

    resp = client.post(
        "/admin/tenants",
        headers=admin_auth,
        json={"tenant_id": tenant_id, "tenant_key": "loja", "tenant_name": "Loja"},
    )
    assert resp.status_code == 200
    assert [n for _, n in criados] == ["Fila IA", "Fila Humano"]

    from app.services import tenants

    config = tenants.ai_config_for(tenant_id, None)
    assert config["ai_team_id"] == 101
    assert config["handoff_team_id"] == 102

    # Chamar de novo (retroativo) não recria nem duplica.
    resp2 = client.post(
        "/admin/tenants",
        headers=admin_auth,
        json={"tenant_id": tenant_id, "tenant_key": "loja", "tenant_name": "Loja"},
    )
    assert resp2.status_code == 200
    assert len(criados) == 2


def test_conversa_nova_e_atribuida_a_fila_ia(client, admin_auth, tenant_id, monkeypatch):
    from app.services import chatwoot, kernel, tenants

    atribuicoes = []

    async def falso_token(_user_id):
        return "token-de-conta"

    async def falso_assign_team(account_id, token, conversation_id, team_id):
        atribuicoes.append((conversation_id, team_id))
        return {}

    async def falso_ask(**kwargs):
        return {"reply": "oi!", "handoff": False}

    async def falso_create_message(*args, **kwargs):
        return {}

    monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
    monkeypatch.setattr(chatwoot, "assign_team", falso_assign_team)
    monkeypatch.setattr(chatwoot, "create_message", falso_create_message)
    monkeypatch.setattr(kernel, "ask", falso_ask)

    _tenant_com_usuario(tenant_id)
    tenants.upsert_ai_config(
        tenant_id=tenant_id,
        chatwoot_inbox_id=None,
        template_id="11111111-1111-1111-1111-111111111111",
        integration_key="chave",
    )
    tenants.set_default_teams(tenant_id, ai_team_id=555, handoff_team_id=666)

    from app.api.agent_bot import _handle_message

    payload = {
        "conversation": {"id": 9001, "inbox_id": 11},
        "content": "oi",
    }
    import asyncio

    asyncio.run(_handle_message(tenant_id, 7, payload))
    assert atribuicoes == [(9001, 555)]

    # Segunda mensagem da mesma conversa: já está na Fila IA, não chama de novo.
    asyncio.run(_handle_message(tenant_id, 7, payload))
    assert atribuicoes == [(9001, 555)]
