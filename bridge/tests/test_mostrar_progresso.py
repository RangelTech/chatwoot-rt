"""Canal externo não tem stream: a mensagem de progresso é permissão por caixa (padrão off)."""

import asyncio

import pytest

pytestmark = pytest.mark.integration

TEMPLATE = "11111111-1111-1111-1111-111111111111"


def _tenant_pronto(tenant_id: str) -> None:
    from app.db import get_connection

    with get_connection() as conn:
        conn.execute(
            """INSERT INTO tenant_links (tenant_id, tenant_key, tenant_name, chatwoot_account_id)
               VALUES (%s, 'loja-prog', 'Loja', 7)""",
            (tenant_id,),
        )
        conn.execute(
            """INSERT INTO user_links (tenant_id, platform_user_id, email, chatwoot_user_id, role)
               VALUES (%s, gen_random_uuid(), 'dono@loja-prog.com', 3, 'administrator')""",
            (tenant_id,),
        )


def _rodar(tenant_id, monkeypatch, *, show_progress):
    from app.api.agent_bot import _handle_message
    from app.services import chatwoot, kernel, tenants

    enviados = []

    async def falso_token(_user_id):
        return "token"

    async def falso_create_message(account_id, token, conversation_id, content, **kwargs):
        enviados.append(content)
        return {}

    async def falso_ask(**kwargs):
        return {"reply": "resposta final", "handoff": False, "artifacts": []}

    monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
    monkeypatch.setattr(chatwoot, "create_message", falso_create_message)
    monkeypatch.setattr(kernel, "ask", falso_ask)
    _tenant_pronto(tenant_id)
    tenants.upsert_ai_config(
        tenant_id=tenant_id,
        chatwoot_inbox_id=11,
        template_id=TEMPLATE,
        integration_key="chave",
        show_progress=show_progress,
    )
    payload = {"conversation": {"id": 5001, "inbox_id": 11}, "content": "oi"}
    asyncio.run(_handle_message(tenant_id, 7, payload))
    return enviados


def test_padrao_corta_o_progresso_e_entrega_so_a_resposta(client, tenant_id, monkeypatch):
    assert _rodar(tenant_id, monkeypatch, show_progress=None) == ["resposta final"]


def test_com_permissao_envia_uma_mensagem_de_progresso_e_a_resposta(client, tenant_id, monkeypatch):
    enviados = _rodar(tenant_id, monkeypatch, show_progress=True)
    assert len(enviados) == 2
    assert enviados[0].startswith("Pensando") and enviados[1] == "resposta final"


def test_admin_grava_e_lista_show_progress_sem_resetar(client, admin_auth, tenant_id):
    from app.services import tenants

    _tenant_pronto(tenant_id)
    base = {
        "tenant_id": tenant_id,
        "chatwoot_inbox_id": 11,
        "template_id": TEMPLATE,
        "integration_key": "chave",
    }
    r = client.post("/admin/ai-config", headers=admin_auth, json={**base, "show_progress": True})
    assert r.status_code == 200, r.text
    assert tenants.ai_config_for(tenant_id, 11)["show_progress"] is True
    client.post("/admin/ai-config", headers=admin_auth, json=base)  # sem o campo: mantém
    assert tenants.ai_config_for(tenant_id, 11)["show_progress"] is True
    client.post("/admin/ai-config", headers=admin_auth, json={**base, "show_progress": False})
    assert tenants.ai_config_for(tenant_id, 11)["show_progress"] is False
