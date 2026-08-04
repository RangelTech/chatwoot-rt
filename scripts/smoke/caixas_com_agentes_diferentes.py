"""Duas caixas do MESMO tenant, cada uma com o seu agente.

O smoke `atendimento_negocio.py` prova que a IA atende. Este prova a coisa que
o cliente pediu e que ninguém tinha como verificar: uma empresa com várias
caixas — WhatsApp da cobrança, Instagram das vendas — e um agente diferente em
cada uma.

A prova precisa ser inequívoca, e por isso o segundo template não é "outro
agente parecido": ele é instruído a começar toda resposta com uma marca. Se a
mensagem que chega na caixa B voltar sem a marca, foi o agente da caixa A que
respondeu — que é exatamente o defeito que este teste existe para pegar, e que
uma comparação de "as duas responderam" não pegaria.

Uso:
    BRIDGE_URL=... BRIDGE_ADMIN_TOKEN=... CHATWOOT_URL=... \
    CHATWOOT_PLATFORM_TOKEN=... AGENT_PLATFORM_URL=... \
    HOMOLOG_MASTER_EMAIL=... HOMOLOG_MASTER_PASSWORD=... \
    python scripts/smoke/caixas_com_agentes_diferentes.py
"""

import os
import sys
import time
import uuid

import httpx

BRIDGE = os.environ["BRIDGE_URL"].rstrip("/")
BRIDGE_TOKEN = os.environ["BRIDGE_ADMIN_TOKEN"]
CHATWOOT = os.environ["CHATWOOT_URL"].rstrip("/")
PLATFORM_TOKEN = os.environ["CHATWOOT_PLATFORM_TOKEN"]
PLATFORM = os.environ["AGENT_PLATFORM_URL"].rstrip("/")
MASTER_EMAIL = os.environ.get("HOMOLOG_MASTER_EMAIL", "master@example.com")
MASTER_PASSWORD = os.environ.get("HOMOLOG_MASTER_PASSWORD", "admin123")
TENANT_EMAIL = os.environ.get("QA_TENANT_EMAIL", "dono@hamburgueriademo.com")
TENANT_PASSWORD = os.environ.get("HOMOLOG_ADMIN_PASSWORD", "homolog-senha-forte-123")

MARCA = "SUPORTE-B:"

checks: list[tuple[str, bool, str]] = []


def _print(texto: str) -> None:
    codec = sys.stdout.encoding or "utf-8"
    print(texto.encode(codec, errors="replace").decode(codec))


def check(nome: str, ok: bool, detalhe: str = "") -> bool:
    checks.append((nome, ok, detalhe))
    extra = f" - {detalhe[:200]}" if detalhe and not ok else ""
    _print(f"  [{'ok ' if ok else 'FAIL'}] {nome}{extra}")
    return ok


def _servico_de_ia(client, uh) -> str | None:
    servicos = client.get(f"{PLATFORM}/api/ai-services", headers=uh).json()
    ativos = [s for s in servicos if s.get("is_active")]
    return (ativos or servicos or [{}])[0].get("id")


def _template_marcado(client, uh, sufixo: str) -> str | None:
    """Template mínimo cuja única função é ser reconhecível na resposta."""
    servico = _servico_de_ia(client, uh)
    if not servico:
        return None
    criado = client.post(
        f"{PLATFORM}/api/templates",
        headers=uh,
        json={"name": f"QA Suporte {sufixo}", "description": "Agente de QA da caixa B"},
    )
    if criado.status_code >= 400:
        return None
    template_id = criado.json()["id"]

    versao = client.post(
        f"{PLATFORM}/api/templates/{template_id}/versions",
        headers=uh,
        json={
            "supervisor_prompt": (
                "Você é o suporte técnico. Comece TODA resposta exatamente com "
                f"'{MARCA}' e depois responda em uma frase curta. Não fale de "
                "cardápio nem de preços de lanche."
            ),
            "supervisor_ai_service_id": servico,
            "max_steps": 2,
            "agents": [],
        },
    )
    if versao.status_code >= 400:
        return None
    client.post(
        f"{PLATFORM}/api/templates/{template_id}/deploy",
        headers=uh,
        json={"version_id": versao.json()["id"]},
    )
    return template_id


def _cria_caixa(client, bridge_headers, tenant_id: str, nome: str) -> dict:
    return client.post(
        f"{BRIDGE}/admin/channels",
        headers=bridge_headers,
        json={
            "tenant_id": tenant_id,
            "provider": "wapi",
            "external_id": f"inst-{nome}",
            "token": "token-de-teste",
        },
    ).json()


def _espera_resposta(client, account_id, agente_token, telefone, limite_s=240) -> str:
    limite = time.time() + limite_s
    while time.time() < limite:
        conversas = client.get(
            f"{CHATWOOT}/api/v1/accounts/{account_id}/conversations",
            headers={"api_access_token": agente_token},
            params={"status": "all", "assignee_type": "all"},
        ).json()
        payload = (conversas.get("data") or {}).get("payload") or []
        atual = next(
            (
                c
                for c in payload
                if telefone
                in str(((c.get("meta") or {}).get("sender") or {}).get("identifier") or "")
            ),
            None,
        )
        if atual:
            mensagens = client.get(
                f"{CHATWOOT}/api/v1/accounts/{account_id}/conversations/{atual['id']}/messages",
                headers={"api_access_token": agente_token},
            ).json()
            itens = mensagens.get("payload") if isinstance(mensagens, dict) else mensagens
            saidas = [m for m in (itens or []) if m.get("message_type") == 1]
            if saidas:
                return saidas[-1].get("content") or ""
        time.sleep(5)
    return ""


def main() -> int:
    sufixo = uuid.uuid4().hex[:6]
    client = httpx.Client(timeout=300.0)
    bridge_headers = {"Authorization": f"Bearer {BRIDGE_TOKEN}", "Content-Type": "application/json"}
    platform_headers = {"api_access_token": PLATFORM_TOKEN}

    master = client.post(
        f"{PLATFORM}/api/auth/login",
        json={"email": MASTER_EMAIL, "password": MASTER_PASSWORD},
    ).json()["token"]
    mh = {"Authorization": f"Bearer {master}"}
    usuarios = client.get(f"{PLATFORM}/api/users", headers=mh).json()
    usuario = next((u for u in usuarios if u["email"] == TENANT_EMAIL), None)
    if not check("tenant de QA existe", usuario is not None):
        return 1

    client.put(
        f"{PLATFORM}/api/users/{usuario['id']}",
        json={"password": TENANT_PASSWORD},
        headers=mh,
    )
    token = client.post(
        f"{PLATFORM}/api/auth/login",
        json={"email": TENANT_EMAIL, "password": TENANT_PASSWORD},
    ).json()["token"]
    uh = {"Authorization": f"Bearer {token}"}

    provision = client.post(f"{PLATFORM}/api/omnichannel/provision", json={}, headers=uh)
    account_id = provision.json().get("chatwoot_account_id")
    if not check("operação provisionada", bool(account_id), provision.text):
        return 1

    templates = client.get(f"{PLATFORM}/api/templates", headers=uh).json()
    template_a = next((t for t in templates if t.get("active_version_id")), None)
    if not check("template do negócio ativo", template_a is not None):
        return 1
    template_b = _template_marcado(client, uh, sufixo)
    if not check("segundo template criado e publicado", bool(template_b)):
        return 1

    integracao = client.post(
        f"{PLATFORM}/api/integrations",
        headers=uh,
        json={"name": f"qa-caixas-{sufixo}", "channel": "api", "template_id": template_a["id"]},
    ).json()

    caixa_a = _cria_caixa(client, bridge_headers, usuario["tenant_id"], f"qa-a-{sufixo}")
    caixa_b = _cria_caixa(client, bridge_headers, usuario["tenant_id"], f"qa-b-{sufixo}")
    if not check(
        "duas caixas criadas no mesmo tenant",
        bool(caixa_a.get("chatwoot_inbox_id") and caixa_b.get("chatwoot_inbox_id")),
        f"{caixa_a} {caixa_b}",
    ):
        return 1

    # A primeira leva a chave; a segunda precisa herdá-la — é o que a tela faz.
    client.post(
        f"{BRIDGE}/admin/ai-config",
        headers=bridge_headers,
        json={
            "tenant_id": usuario["tenant_id"],
            "chatwoot_inbox_id": caixa_a["chatwoot_inbox_id"],
            "template_id": template_a["id"],
            "integration_key": integracao.get("api_key"),
            "autopilot": True,
        },
    )
    vinculo_b = client.put(
        f"{PLATFORM}/api/omnichannel/inboxes/{caixa_b['chatwoot_inbox_id']}/ia",
        headers=uh,
        json={"template_id": template_b, "autopilot": True},
    )
    check("caixa B vinculada pela rota da plataforma", vinculo_b.status_code == 200, vinculo_b.text)

    listagem = client.get(f"{PLATFORM}/api/omnichannel/inboxes", headers=uh).json()
    por_caixa = {c["chatwoot_inbox_id"]: (c.get("ai") or {}) for c in listagem.get("inboxes", [])}
    check(
        "a tela mostra um agente diferente em cada caixa",
        por_caixa.get(caixa_a["chatwoot_inbox_id"], {}).get("template_id") == template_a["id"]
        and por_caixa.get(caixa_b["chatwoot_inbox_id"], {}).get("template_id") == template_b,
        str(por_caixa)[:300],
    )
    check(
        "a caixa B herdou a chave de integração",
        bool(por_caixa.get(caixa_b["chatwoot_inbox_id"], {}).get("has_integration_key")),
    )

    # Agent bot em cada inbox, senão o Chatwoot não chama a ponte.
    agente_token = None
    for candidato in range(1, 120):
        corpo = client.get(
            f"{CHATWOOT}/platform/api/v1/users/{candidato}", headers=platform_headers
        )
        if corpo.status_code == 200 and corpo.json().get("email") == TENANT_EMAIL:
            agente_token = corpo.json()["access_token"]
            break
    if not check("usuário espelhado no Chatwoot", bool(agente_token)):
        return 1

    bot = client.post(
        f"{CHATWOOT}/platform/api/v1/agent_bots",
        headers=platform_headers,
        json={
            "name": f"IA QA {sufixo}",
            "outgoing_url": f"{BRIDGE}/agent-bot",
            "account_id": account_id,
        },
    ).json()
    for caixa in (caixa_a, caixa_b):
        client.post(
            f"{CHATWOOT}/api/v1/accounts/{account_id}/inboxes/"
            f"{caixa['chatwoot_inbox_id']}/set_agent_bot",
            headers={"api_access_token": agente_token},
            json={"agent_bot": bot.get("id")},
        )

    respostas = {}
    for rotulo, caixa, pergunta in (
        ("A", caixa_a, "oi, o que voces vendem?"),
        ("B", caixa_b, "oi, preciso de ajuda tecnica"),
    ):
        telefone = f"5511{uuid.uuid4().int % 100000000:08d}"
        entrada = client.post(
            f"{BRIDGE}{caixa['webhook_path']}",
            json={
                "phone": f"{telefone}@c.us",
                "text": pergunta,
                "messageId": f"msg-{rotulo}-{sufixo}",
            },
        )
        check(f"caixa {rotulo}: mensagem aceita", entrada.json().get("status") == "accepted",
              entrada.text)
        respostas[rotulo] = _espera_resposta(client, account_id, agente_token, telefone)
        _print(f"    caixa {rotulo} respondeu: {respostas[rotulo][:120]}")

    check("caixa A respondeu", bool(respostas["A"].strip()))
    check("caixa B respondeu", bool(respostas["B"].strip()))
    # O ponto do teste: a resposta da caixa B tem que vir do agente da caixa B.
    check(
        "cada caixa respondeu com o SEU agente",
        MARCA.lower() in respostas["B"].lower() and MARCA.lower() not in respostas["A"].lower(),
        f"A={respostas['A'][:80]} | B={respostas['B'][:80]}",
    )

    falhas = [c for c in checks if not c[1]]
    _print(f"\n{len(checks) - len(falhas)}/{len(checks)} checks")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
