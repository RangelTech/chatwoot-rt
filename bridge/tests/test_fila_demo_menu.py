"""Produto-08: fila de demonstração sem IA (menu "digite 1, digite 2").

Reaproveita o mesmo webhook do Agent Bot e a mesma tabela `conversation_states`
do fluxo de IA/Humano — mas o branch em `agent_bot.py` decide pelo `inbox_id`
ANTES de tocar em kernel/`ai_config_for`. Os testes aqui protegem exatamente
isso: cada opção do menu responde certo, entrada inválida tem fallback claro,
e — o mais importante — a fila demo nunca aciona o kernel nem o fluxo de IA, e
vice-versa.
"""

import asyncio

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


@pytest.fixture
def chatwoot_falso(monkeypatch):
    """Stub do Chatwoot: grava tudo que a fila demo tentou fazer, sem HTTP real."""
    from app.services import chatwoot

    mensagens: list[tuple[int, str, bool]] = []
    atribuicoes: list[tuple[int, int]] = []
    status: list[tuple[int, str]] = []

    async def falso_token(_user_id):
        return "token-de-conta"

    async def falso_create_message(_account_id, _token, conversation_id, content, **kwargs):
        mensagens.append((conversation_id, content, kwargs.get("private", False)))
        return {}

    async def falso_assign_team(_account_id, _token, conversation_id, team_id):
        atribuicoes.append((conversation_id, team_id))
        return {}

    async def falso_toggle_status(_account_id, _token, conversation_id, novo_status):
        status.append((conversation_id, novo_status))
        return {}

    monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
    monkeypatch.setattr(chatwoot, "create_message", falso_create_message)
    monkeypatch.setattr(chatwoot, "assign_team", falso_assign_team)
    monkeypatch.setattr(chatwoot, "toggle_status", falso_toggle_status)

    return {"mensagens": mensagens, "atribuicoes": atribuicoes, "status": status}


def _menu_config(tenant_id: str, inbox_id: int = 900) -> dict:
    from app.services import tenants

    return tenants.upsert_menu_bot_config(
        tenant_id=tenant_id,
        chatwoot_inbox_id=inbox_id,
        team_vendas_id=501,
        team_suporte_id=502,
        team_financeiro_id=503,
    )


def _mandar(tenant_id: str, conversation_id: int, content: str, config: dict) -> None:
    from app.api.agent_bot import _handle_menu_bot

    asyncio.run(_handle_menu_bot(tenant_id, 7, conversation_id, content, config))


def test_primeira_mensagem_manda_o_menu(client, tenant_id, chatwoot_falso):
    _tenant_com_usuario(tenant_id)
    config = _menu_config(tenant_id)

    _mandar(tenant_id, 1001, "oi", config)

    assert len(chatwoot_falso["mensagens"]) == 1
    conversa, texto, _ = chatwoot_falso["mensagens"][0]
    assert conversa == 1001
    assert "1 - Falar com vendas" in texto
    assert "0 - Encerrar" in texto

    from app.services import tenants

    assert tenants.menu_step_for(tenant_id, 1001) == "root"


@pytest.mark.parametrize(
    "opcao,esperado_no_texto,campo_team,team_id",
    [
        ("1", "vendas", "team_vendas_id", 501),
        ("2", "Suporte", "team_suporte_id", 502),
        ("3", "Financeiro", "team_financeiro_id", 503),
    ],
)
def test_cada_opcao_do_menu_responde_e_atribui_o_team_certo(
    client, tenant_id, chatwoot_falso, opcao, esperado_no_texto, campo_team, team_id
):
    _tenant_com_usuario(tenant_id)
    config = _menu_config(tenant_id)

    _mandar(tenant_id, 2001, "oi", config)  # entra no menu
    _mandar(tenant_id, 2001, opcao, config)

    _, texto, _ = chatwoot_falso["mensagens"][-1]
    assert esperado_no_texto.lower() in texto.lower()
    assert "digite 0" in texto.lower()
    assert chatwoot_falso["atribuicoes"] == [(2001, team_id)]

    from app.services import tenants

    assert tenants.menu_step_for(tenant_id, 2001) == f"option:{opcao}"


def test_opcao_0_encerra_e_resolve_a_conversa(client, tenant_id, chatwoot_falso):
    _tenant_com_usuario(tenant_id)
    config = _menu_config(tenant_id)

    _mandar(tenant_id, 3001, "oi", config)
    _mandar(tenant_id, 3001, "0", config)

    _, texto, _ = chatwoot_falso["mensagens"][-1]
    assert "encerrado" in texto.lower()
    assert chatwoot_falso["status"] == [(3001, "resolved")]
    assert chatwoot_falso["atribuicoes"] == []  # opção 0 nunca atribui Team


def test_entrada_invalida_no_menu_tem_fallback_claro_e_nao_trava(client, tenant_id, chatwoot_falso):
    _tenant_com_usuario(tenant_id)
    config = _menu_config(tenant_id)

    _mandar(tenant_id, 4001, "oi", config)
    _mandar(tenant_id, 4001, "banana", config)

    _, texto, _ = chatwoot_falso["mensagens"][-1]
    assert "não entendi" in texto.lower()
    assert "1, 2, 3 ou 0" in texto

    from app.services import tenants

    # Não trava nem avança de estado: continua esperando uma opção válida.
    assert tenants.menu_step_for(tenant_id, 4001) == "root"

    # E a conversa continua respondendo normalmente depois do erro.
    _mandar(tenant_id, 4001, "2", config)
    assert chatwoot_falso["atribuicoes"] == [(4001, 502)]


def test_entrada_invalida_dentro_de_uma_opcao_tambem_tem_fallback(
    client, tenant_id, chatwoot_falso
):
    _tenant_com_usuario(tenant_id)
    config = _menu_config(tenant_id)

    _mandar(tenant_id, 4101, "oi", config)
    _mandar(tenant_id, 4101, "1", config)
    _mandar(tenant_id, 4101, "qualquer coisa", config)

    _, texto, _ = chatwoot_falso["mensagens"][-1]
    assert "digite 0" in texto.lower()

    from app.services import tenants

    assert tenants.menu_step_for(tenant_id, 4101) == "option:1"


def test_digitar_0_dentro_de_uma_opcao_volta_ao_menu_principal(client, tenant_id, chatwoot_falso):
    _tenant_com_usuario(tenant_id)
    config = _menu_config(tenant_id)

    _mandar(tenant_id, 4201, "oi", config)
    _mandar(tenant_id, 4201, "3", config)
    _mandar(tenant_id, 4201, "0", config)

    _, texto, _ = chatwoot_falso["mensagens"][-1]
    assert "1 - Falar com vendas" in texto

    from app.services import tenants

    assert tenants.menu_step_for(tenant_id, 4201) == "root"


def test_multiplas_conversas_simultaneas_nao_cruzam_estado(client, tenant_id, chatwoot_falso):
    _tenant_com_usuario(tenant_id)
    config = _menu_config(tenant_id)

    _mandar(tenant_id, 5001, "oi", config)
    _mandar(tenant_id, 5002, "oi", config)
    _mandar(tenant_id, 5001, "1", config)  # conversa 1 escolhe vendas
    _mandar(tenant_id, 5002, "2", config)  # conversa 2 escolhe suporte

    from app.services import tenants

    assert tenants.menu_step_for(tenant_id, 5001) == "option:1"
    assert tenants.menu_step_for(tenant_id, 5002) == "option:2"
    assert set(chatwoot_falso["atribuicoes"]) == {(5001, 501), (5002, 502)}


# --------------------------------------------------------------------------
# Isolamento com o fluxo de IA — o ponto mais importante desta spec.
# --------------------------------------------------------------------------


def test_webhook_da_inbox_demo_nunca_chama_o_kernel(client, tenant_id, chatwoot_falso, monkeypatch):
    """Ponta a ponta pelo webhook real: uma mensagem chegando na inbox da fila
    demo precisa cair em `_handle_menu_bot`, nunca em `_handle_message`
    (que é quem chama `kernel.ask`)."""
    from app.services import kernel

    kernel_chamado = []

    async def kernel_nao_deveria_ser_chamado(**kwargs):
        kernel_chamado.append(kwargs)
        return {"reply": "não deveria responder", "handoff": False}

    monkeypatch.setattr(kernel, "ask", kernel_nao_deveria_ser_chamado)

    _tenant_com_usuario(tenant_id)
    _menu_config(tenant_id, inbox_id=900)

    resp = client.post(
        "/agent-bot",
        json={
            "event": "message_created",
            "message_type": "incoming",
            "account": {"id": 7},
            "conversation": {"id": 6001, "inbox_id": 900},
            "content": "oi",
        },
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "accepted"

    # background task roda no mesmo loop do TestClient (starlette a executa
    # antes de devolver a resposta em modo síncrono de teste).
    assert kernel_chamado == []
    assert len(chatwoot_falso["mensagens"]) == 1
    assert "1 - Falar com vendas" in chatwoot_falso["mensagens"][0][1]


def test_webhook_de_outra_inbox_nunca_aciona_o_menu_bot(
    client, tenant_id, chatwoot_falso, monkeypatch
):
    """O inverso: uma inbox que NÃO é a da fila demo precisa continuar caindo
    no fluxo de IA normal, mesmo com `menu_bot_config` cadastrada para outra
    inbox do mesmo tenant."""
    from app.services import kernel, tenants

    async def falso_ask(**kwargs):
        return {"reply": "resposta da IA", "handoff": False}

    monkeypatch.setattr(kernel, "ask", falso_ask)

    _tenant_com_usuario(tenant_id)
    _menu_config(tenant_id, inbox_id=900)  # fila demo é a inbox 900
    tenants.upsert_ai_config(
        tenant_id=tenant_id,
        chatwoot_inbox_id=None,
        template_id="11111111-1111-1111-1111-111111111111",
        integration_key="chave",
    )

    resp = client.post(
        "/agent-bot",
        json={
            "event": "message_created",
            "message_type": "incoming",
            "account": {"id": 7},
            "conversation": {"id": 6101, "inbox_id": 42},  # inbox diferente
            "content": "quero saber o preco",
        },
    )
    assert resp.status_code == 200

    assert any(texto == "resposta da IA" for _, texto, _ in chatwoot_falso["mensagens"])
    # A fila demo nunca escreveu nesta conversa nem criou menu_step para ela.
    assert tenants.menu_step_for(tenant_id, 6101) == ""


def test_conversation_states_do_menu_bot_nao_interfere_no_state_da_ia(
    client, tenant_id, chatwoot_falso
):
    """Mesmo tabela (`conversation_states`), linha por conversa: gravar
    `menu_step` numa conversa da fila demo não deve tocar em `state`/
    `session_id`, os campos que o fluxo de IA usa para saber quem está no
    comando."""
    from app.services import tenants

    _tenant_com_usuario(tenant_id)
    config = _menu_config(tenant_id)

    _mandar(tenant_id, 7001, "oi", config)
    _mandar(tenant_id, 7001, "1", config)

    row = tenants.conversation_state(tenant_id, 7001)
    assert row["menu_step"] == "option:1"
    # `state` nunca foi escrito pelo menu bot: continua no default do fluxo de IA.
    assert row["state"] == "ai_active"
    assert row["session_id"] == ""


# --------------------------------------------------------------------------
# Provisionamento (opt-in por tenant, não automático)
# --------------------------------------------------------------------------


def test_provision_menu_demo_cria_inbox_e_teams_uma_vez(client, admin_auth, tenant_id, monkeypatch):
    from app.services import chatwoot

    caixas_criadas = []
    times_criados = []

    async def falso_token(_user_id):
        return "token-de-conta"

    async def falsa_lista_inboxes(_account_id, _token):
        return []

    async def falsa_cria_inbox(account_id, token, name, webhook_url):
        caixas_criadas.append(name)
        return {"id": 900}

    async def falso_cria_bot(account_id, name, outgoing_url):
        return {"id": 77}

    async def falso_set_bot(*args, **kwargs):
        return {}

    async def falso_cria_team(account_id, token, name):
        times_criados.append(name)
        return {"id": 500 + len(times_criados)}

    monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
    monkeypatch.setattr(chatwoot, "list_inboxes", falsa_lista_inboxes)
    monkeypatch.setattr(chatwoot, "create_api_inbox", falsa_cria_inbox)
    monkeypatch.setattr(chatwoot, "create_agent_bot", falso_cria_bot)
    monkeypatch.setattr(chatwoot, "set_agent_bot", falso_set_bot)
    monkeypatch.setattr(chatwoot, "create_team", falso_cria_team)

    _tenant_com_usuario(tenant_id)

    resp = client.post(
        "/admin/menu-demo", headers=admin_auth, json={"tenant_id": tenant_id}
    )
    assert resp.status_code == 200
    corpo = resp.json()
    assert corpo["created"] is True
    assert corpo["chatwoot_inbox_id"] == 900
    assert caixas_criadas == ["Fila Demo IVR"]
    assert times_criados == ["Vendas Demo", "Suporte Demo", "Financeiro Demo"]

    from app.services import tenants

    config = tenants.menu_bot_config_for(tenant_id, 900)
    assert config["team_vendas_id"] == 501
    assert config["team_suporte_id"] == 502
    assert config["team_financeiro_id"] == 503

    # Chamar de novo é idempotente: não recria inbox nem Teams.
    resp2 = client.post(
        "/admin/menu-demo", headers=admin_auth, json={"tenant_id": tenant_id}
    )
    assert resp2.status_code == 200
    assert resp2.json()["created"] is False
    assert caixas_criadas == ["Fila Demo IVR"]
    assert times_criados == ["Vendas Demo", "Suporte Demo", "Financeiro Demo"]


def test_provision_menu_demo_sem_tenant_provisionado_da_409(client, admin_auth, tenant_id):
    resp = client.post(
        "/admin/menu-demo", headers=admin_auth, json={"tenant_id": tenant_id}
    )
    assert resp.status_code == 409
