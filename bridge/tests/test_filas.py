"""Fase F: a ponte consulta o Luar para decidir quem responde no modo filas."""

import asyncio

import pytest

pytestmark = pytest.mark.integration

TEMPLATE_A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
TEMPLATE_B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"


def _tenant_pronto(tenant_id: str, *, autopilot: bool = True) -> None:
    from app.db import get_connection
    from app.services import tenants

    with get_connection() as conn:
        conn.execute(
            """INSERT INTO tenant_links (tenant_id, tenant_key, tenant_name, chatwoot_account_id)
               VALUES (%s, 'loja-filas', 'Loja', 7)""",
            (tenant_id,),
        )
        conn.execute(
            """INSERT INTO user_links (tenant_id, platform_user_id, email, chatwoot_user_id, role)
               VALUES (%s, gen_random_uuid(), 'dono@loja-filas.com', 3, 'administrator')""",
            (tenant_id,),
        )
    tenants.upsert_ai_config(
        tenant_id=tenant_id, chatwoot_inbox_id=11, template_id=TEMPLATE_A, integration_key="chave"
    )


class Cenario:
    """Fakes do Luar, do Chatwoot e do kernel com registro do que foi enviado."""

    def __init__(self, monkeypatch):
        from app.config import settings
        from app.services import chatwoot, kernel, routing

        monkeypatch.setattr(settings, "rt_internal_url", "http://luar.test")
        monkeypatch.setattr(settings, "rt_internal_token", "t")
        self.decisions = []  # fila de respostas do resolve (a ultima se repete)
        self.resolve_calls = []
        self.handoffs = []
        self.enviadas = []
        self.prompts = []
        self.entries = []
        self.kernel_result = {
            "reply": "ola",
            "handoff": False,
            "handoff_detail": {},
            "artifacts": [],
        }

        async def falso_resolve(account_id, conversation_id, legacy=None):
            self.resolve_calls.append(legacy)
            if not self.decisions:
                return None
            return self.decisions.pop(0) if len(self.decisions) > 1 else self.decisions[0]

        async def falso_history(account_id, conversation_id):
            return self.entries

        async def falso_destinations(account_id, conversation_id):
            return [{"id": 9, "name": "financeiro", "description": "cobranca e boletos"}]

        async def falso_handoff(account_id, conversation_id, **kw):
            self.handoffs.append(kw)
            return {"ok": True}

        async def falso_token(_uid):
            return "token"

        async def falso_create(account_id, token, conversation_id, content, **kw):
            self.enviadas.append((content, kw))
            return {}

        async def falso_ask(**kw):
            self.prompts.append(kw)
            return self.kernel_result

        monkeypatch.setattr(routing, "resolve", falso_resolve)
        monkeypatch.setattr(routing, "history", falso_history)
        monkeypatch.setattr(routing, "destinations", falso_destinations)
        monkeypatch.setattr(routing, "handoff", falso_handoff)
        monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
        monkeypatch.setattr(chatwoot, "create_message", falso_create)
        monkeypatch.setattr(kernel, "ask", falso_ask)


def _decisao(respondent="ia", agent=TEMPLATE_A, mode="filas", reason="fila_ia"):
    return {
        "respondent": respondent,
        "agent": agent,
        "routing_mode": mode,
        "reason": reason,
        "queue_id": 1,
    }


def _msg(message_id, content="oi", conversation_id=5001):
    return {
        "event": "message_created",
        "message_type": "incoming",
        "id": message_id,
        "content": content,
        "account": {"id": 7},
        "conversation": {"id": conversation_id, "inbox_id": 11},
    }


@pytest.fixture
def cenario(client, tenant_id, monkeypatch):
    _tenant_pronto(tenant_id)
    return Cenario(monkeypatch)


def test_filas_ia_responde_com_marca_de_origem(client, cenario):
    cenario.decisions = [_decisao()]
    r = client.post("/agent-bot", json=_msg(1))
    assert r.json()["status"] == "accepted"
    publicas = [(c, kw) for c, kw in cenario.enviadas if not kw.get("private")]
    assert publicas and publicas[0][0] == "ola"
    assert publicas[0][1]["content_attributes"] == {"rt_origin": "ia", "rt_agent": TEMPLATE_A}
    assert cenario.prompts[0]["template_id"] == TEMPLATE_A


def test_filas_humano_nao_chama_o_kernel(client, cenario):
    cenario.decisions = [_decisao("humano", reason="responsavel_humano")]
    assert client.post("/agent-bot", json=_msg(2)).json()["status"] == "humano"
    assert cenario.prompts == []


def test_mensagem_duplicada_e_ignorada(client, cenario):
    cenario.decisions = [_decisao()]
    assert client.post("/agent-bot", json=_msg(3)).json()["status"] == "accepted"
    assert client.post("/agent-bot", json=_msg(3)).json()["status"] == "duplicate"
    assert len(cenario.prompts) == 1


def test_mensagens_fora_de_ordem_respondem_cada_uma_uma_vez(client, cenario):
    cenario.decisions = [_decisao()]
    for message_id in (12, 10, 11, 10, 12):
        client.post("/agent-bot", json=_msg(message_id))
    assert len(cenario.prompts) == 3


def test_legado_e_sombra_usam_o_caminho_antigo_e_informam_o_legado(client, cenario, monkeypatch):
    from app.api import agent_bot

    chamadas = []

    async def falso_legado(tenant_id, account_id, payload):
        chamadas.append(payload["id"])

    monkeypatch.setattr(agent_bot, "_handle_message", falso_legado)
    for modo in ("legado", "sombra"):
        cenario.decisions = [_decisao(mode=modo)]
        client.post("/agent-bot", json=_msg(20 if modo == "legado" else 21))
    assert chamadas == [20, 21]
    assert cenario.resolve_calls == ["ia", "ia"]  # o estado legado informado ao Luar


def test_falha_na_consulta_cai_no_legado(client, cenario, monkeypatch):
    from app.api import agent_bot

    chamadas = []

    async def falso_legado(tenant_id, account_id, payload):
        chamadas.append(payload["id"])

    monkeypatch.setattr(agent_bot, "_handle_message", falso_legado)
    cenario.decisions = []  # resolve devolve None
    client.post("/agent-bot", json=_msg(30))
    assert chamadas == [30]


def test_resposta_descartada_quando_humano_assume_durante_a_execucao(client, cenario):
    cenario.decisions = [_decisao(), _decisao("humano", reason="responsavel_humano")]
    client.post("/agent-bot", json=_msg(40))
    assert len(cenario.prompts) == 1
    assert [c for c, kw in cenario.enviadas if not kw.get("private")] == []


def test_repasse_chama_o_luar_com_fila_e_resumo(client, cenario):
    cenario.decisions = [_decisao()]
    cenario.kernel_result = {
        "reply": "vou passar para o financeiro",
        "handoff": True,
        "handoff_detail": {"queue": "financeiro", "summary": "boleto vencido"},
        "artifacts": [],
    }
    client.post("/agent-bot", json=_msg(50))
    assert cenario.handoffs and cenario.handoffs[0]["queue"] == "financeiro"
    assert cenario.handoffs[0]["summary"] == "boleto vencido"
    assert "financeiro: cobranca e boletos" in cenario.prompts[0]["message"]


def test_agente_novo_recebe_historico_com_nota_marcada_e_sessao_nova(client, cenario):
    cenario.entries = [
        {"id": 1, "role": "cliente", "content": "quero cancelar", "internal": False},
        {"id": 2, "role": "ia", "agent": TEMPLATE_A, "content": "posso ajudar", "internal": False},
        {"id": 3, "role": "nota_interna", "content": "cliente VIP", "internal": True},
    ]
    cenario.decisions = [_decisao(agent=TEMPLATE_A)]
    client.post("/agent-bot", json=_msg(60, "e entao?"))
    cenario.decisions = [_decisao(agent=TEMPLATE_B)]
    client.post("/agent-bot", json=_msg(61, "alguem ai?"))
    a, b = cenario.prompts
    assert a["session_id"] != b["session_id"]
    prompt_b = b["message"]
    assert "Cliente: quero cancelar" in prompt_b
    assert "posso ajudar" in prompt_b  # B nao e o autor
    assert "Nota interna (nota interna - nao repetir ao cliente): cliente VIP" in prompt_b
    assert "Nunca repita ao cliente" in prompt_b
    assert prompt_b.endswith("Mensagem do cliente: alguem ai?")
    # o autor da resposta antiga nao recebe a propria fala de volta
    assert "posso ajudar" not in a["message"]


def test_kernel_fora_libera_a_mensagem_e_deixa_nota_para_humano(client, cenario, monkeypatch):
    from app.services import kernel

    async def ask_falha(**kw):
        raise kernel.KernelError("fora")

    monkeypatch.setattr(kernel, "ask", ask_falha)
    cenario.decisions = [_decisao()]
    client.post("/agent-bot", json=_msg(70))
    assert any(kw.get("private") for _, kw in cenario.enviadas)
    # a reentrega da mesma mensagem nao e tratada como duplicada
    monkeypatch.setattr(kernel, "ask", lambda **kw: asyncio.sleep(0, cenario.kernel_result))
    assert client.post("/agent-bot", json=_msg(70)).json()["status"] == "accepted"


def test_parse_handoff_formatos():
    from app.services.kernel import parse_handoff

    assert parse_handoff("oi [[HANDOFF]]") == ("oi", True, {"queue": None, "summary": None})
    assert parse_handoff("passo [[HANDOFF:financeiro|boleto vencido]]") == (
        "passo",
        True,
        {"queue": "financeiro", "summary": "boleto vencido"},
    )
    assert parse_handoff("oi", {"fila": "vendas", "resumo": "quer comprar"})[2] == {
        "queue": "vendas",
        "summary": "quer comprar",
    }
    assert parse_handoff("oi", True)[1] is True
    assert parse_handoff("so resposta") == ("so resposta", False, {"queue": None, "summary": None})


def test_recover_unanswered_reprocessa_uma_vez(monkeypatch):
    import asyncio

    from app.api import agent_bot

    calls = {"handled": [], "claimed": set(), "released": []}
    item = {
        "account_id": 7,
        "conversation_id": 3,
        "inbox_id": 9,
        "message": {"id": 55, "content": "oi?", "message_type": "incoming"},
    }

    async def fake_pending(minutes=15):
        return [item]

    async def fake_resolve(account_id, conversation_id, legacy=None):
        return {"respondent": "ia", "routing_mode": "filas"}

    async def fake_handle(tenant_id, account_id, payload, decision):
        calls["handled"].append(payload["id"])

    monkeypatch.setattr(agent_bot.routing, "configured", lambda: True)
    monkeypatch.setattr(agent_bot.routing, "pending", fake_pending)
    monkeypatch.setattr(agent_bot.routing, "resolve", fake_resolve)
    monkeypatch.setattr(agent_bot, "_tenant_by_account", lambda account_id: {"tenant_id": "t1"})
    monkeypatch.setattr(agent_bot, "_handle_message_filas", fake_handle)
    released = calls["released"]
    monkeypatch.setattr(agent_bot.tenants, "release_message", lambda t, m: released.append(m))
    monkeypatch.setattr(
        agent_bot.tenants,
        "claim_message",
        lambda t, m: calls["claimed"].add(m) or True,
    )
    assert asyncio.run(agent_bot.recover_unanswered(15)) == 1
    assert calls["handled"] == [55]
    assert calls["released"] == [55] and calls["claimed"] == {55}
