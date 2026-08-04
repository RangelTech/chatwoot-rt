"""Cada caixa de atendimento pode ter o seu próprio agente.

Um tenant tem várias caixas — WhatsApp, Instagram, site — e não faz sentido que
todas sejam atendidas pelo mesmo template: quem responde no Instagram da loja
não é quem responde no WhatsApp do financeiro. O banco já guardava a
configuração por caixa (`tenant_ai_config` com UNIQUE por tenant+inbox); o que
faltava era conseguir ver e escolher isso sem chamar a API na unha.

Os dois pontos que estes testes protegem:

1. a lista vem do Chatwoot, não da ponte — caixa criada dentro do próprio
   Chatwoot (um Instagram conectado pela tela) nunca passou por aqui, e é
   exatamente nela que alguém vai querer ligar a IA;
2. configurar uma caixa nova pela tela herda a chave de integração do tenant —
   sem isso a caixa fica configurada e muda, porque quem escolhe o template na
   UI não sabe que existe uma chave por trás.
"""

import pytest

pytestmark = pytest.mark.integration


@pytest.fixture
def chatwoot_falso(monkeypatch):
    """Chatwoot com duas caixas: uma criada pela ponte, outra criada lá dentro."""
    from app.services import chatwoot

    async def falso_token(_user_id):
        return "token-de-conta"

    async def falsas_caixas(_account_id, _token):
        return [
            {"id": 11, "name": "wapi:inst-abc", "channel_type": "Channel::Api"},
            {"id": 22, "name": "Instagram da loja", "channel_type": "Channel::FacebookPage"},
        ]

    monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
    monkeypatch.setattr(chatwoot, "list_inboxes", falsas_caixas)


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


def test_lista_traz_caixa_que_a_ponte_nunca_criou(client, admin_auth, tenant_id, chatwoot_falso):
    _tenant_com_usuario(tenant_id)

    corpo = client.get(f"/admin/ai-config/{tenant_id}", headers=admin_auth).json()

    nomes = {c["chatwoot_inbox_id"]: c["name"] for c in corpo["inboxes"]}
    assert nomes == {11: "wapi:inst-abc", 22: "Instagram da loja"}
    assert all(c["ai"] is None for c in corpo["inboxes"])


def test_cada_caixa_guarda_o_seu_template(client, admin_auth, tenant_id, chatwoot_falso):
    _tenant_com_usuario(tenant_id)
    financeiro = "11111111-1111-1111-1111-111111111111"
    vendas = "22222222-2222-2222-2222-222222222222"

    for inbox, template in ((11, financeiro), (22, vendas)):
        resposta = client.post(
            "/admin/ai-config",
            headers=admin_auth,
            json={
                "tenant_id": tenant_id,
                "chatwoot_inbox_id": inbox,
                "template_id": template,
                "integration_key": "chave-do-tenant",
            },
        )
        assert resposta.status_code == 200

    corpo = client.get(f"/admin/ai-config/{tenant_id}", headers=admin_auth).json()
    por_caixa = {c["chatwoot_inbox_id"]: c["ai"]["template_id"] for c in corpo["inboxes"]}
    assert por_caixa == {11: financeiro, 22: vendas}
    # A chave existe, mas não volta em claro para ninguém.
    assert all(c["ai"]["has_integration_key"] for c in corpo["inboxes"])
    assert "chave-do-tenant" not in resposta.text


def test_caixa_nova_herda_a_chave_de_integracao(client, admin_auth, tenant_id, chatwoot_falso):
    """A tela manda template e autopilot, nunca a chave — ela é detalhe de
    máquina. Sem herança, a segunda caixa nasceria sem chave e ficaria muda."""
    _tenant_com_usuario(tenant_id)
    client.post(
        "/admin/ai-config",
        headers=admin_auth,
        json={
            "tenant_id": tenant_id,
            "chatwoot_inbox_id": 11,
            "template_id": "11111111-1111-1111-1111-111111111111",
            "integration_key": "chave-do-tenant",
        },
    )

    client.post(
        "/admin/ai-config",
        headers=admin_auth,
        json={
            "tenant_id": tenant_id,
            "chatwoot_inbox_id": 22,
            "template_id": "22222222-2222-2222-2222-222222222222",
        },
    )

    from app.services import tenants

    config = tenants.ai_config_for(tenant_id, 22)
    assert config["integration_key_encrypted"]
    from app.crypto import decrypt

    assert decrypt(config["integration_key_encrypted"]) == "chave-do-tenant"


def test_caixa_sem_config_cai_no_padrao_do_tenant(client, admin_auth, tenant_id, chatwoot_falso):
    """Config com inbox NULL é o padrão. Mostrar a caixa como "sem IA" quando
    ela cai no padrão faria alguém reconfigurar o que já funcionava."""
    _tenant_com_usuario(tenant_id)
    client.post(
        "/admin/ai-config",
        headers=admin_auth,
        json={
            "tenant_id": tenant_id,
            "chatwoot_inbox_id": None,
            "template_id": "33333333-3333-3333-3333-333333333333",
            "integration_key": "chave-do-tenant",
        },
    )

    corpo = client.get(f"/admin/ai-config/{tenant_id}", headers=admin_auth).json()
    assert corpo["default"]["template_id"] == "33333333-3333-3333-3333-333333333333"
    assert all(c["inherits_default"] for c in corpo["inboxes"])
