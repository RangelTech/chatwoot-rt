"""Smoke de negócio: cliente escreve no canal, a IA do tenant responde.

Diferente do `omnichannel_e2e.py`, que prova o encanamento com o stub, aqui a
resposta vem do agente real do tenant — com template, modelo e datasource de
produção. É o teste que mostra que a operação atende de verdade.

Uso:
    BRIDGE_URL=... BRIDGE_ADMIN_TOKEN=... CHATWOOT_URL=... \
    CHATWOOT_PLATFORM_TOKEN=... AGENT_PLATFORM_URL=... \
    python scripts/smoke/atendimento_negocio.py
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
TENANT_PASSWORD = os.environ.get("HOMOLOG_ADMIN_PASSWORD", "homolog-senha-forte-123")

# Cada cenário: quem é o tenant, qual template atende, o que o cliente pergunta
# e o que precisa aparecer na resposta para ela ser considerada útil.
CENARIOS = [
    {
        "nome": "hamburgueria",
        "admin_email": "dono@hamburgueriademo.com",
        "template": "Atendimento Hamburgueria",
        "pergunta": "boa noite! quais hamburgueres voces tem e quanto custa o mais barato?",
        "espera": ["burger", "r$"],
    },
    {
        "nome": "ferragista",
        "admin_email": "dono@lojademo.com",
        "template": "Balcao de Vendas",
        "pergunta": "bom dia, voces tem furadeira? qual o preco e tem em estoque?",
        "espera": ["furadeira", "289"],
    },
]

checks: list[tuple[str, bool, str]] = []


def check(nome: str, ok: bool, detalhe: str = "") -> bool:
    checks.append((nome, ok, detalhe))
    extra = f" - {detalhe[:200]}" if detalhe and not ok else ""
    _print(f"  [{'ok ' if ok else 'FAIL'}] {nome}{extra}")
    return ok


def _print(texto: str) -> None:
    """Console do Windows ainda usa cp1252: emoji da resposta não pode
    derrubar o relatório do teste."""
    codec = sys.stdout.encoding or "utf-8"
    print(texto.encode(codec, errors="replace").decode(codec))


def _saidas(client, account_id, conversation_id, token) -> list:
    """Mensagens que saíram para o cliente nesta conversa."""
    corpo = client.get(
        f"{CHATWOOT}/api/v1/accounts/{account_id}/conversations/{conversation_id}/messages",
        headers={"api_access_token": token},
    ).json()
    itens = corpo.get("payload") if isinstance(corpo, dict) else corpo
    return [m for m in (itens or []) if m.get("message_type") == 1]


def main() -> None:
    client = httpx.Client(timeout=300.0)
    bridge_headers = {"Authorization": f"Bearer {BRIDGE_TOKEN}", "Content-Type": "application/json"}
    platform_headers = {"api_access_token": PLATFORM_TOKEN}

    master = client.post(
        f"{PLATFORM}/api/auth/login",
        json={"email": MASTER_EMAIL, "password": MASTER_PASSWORD},
    ).json()["token"]
    mh = {"Authorization": f"Bearer {master}"}
    usuarios = client.get(f"{PLATFORM}/api/users", headers=mh).json()

    for cenario in CENARIOS:
        print(f"\n=== {cenario['nome']} ===")
        usuario = next((u for u in usuarios if u["email"] == cenario["admin_email"]), None)
        if not check(f"{cenario['nome']}: tenant existe", usuario is not None):
            continue

        # Garante uma senha conhecida sem tocar em mais nada do tenant.
        client.put(
            f"{PLATFORM}/api/users/{usuario['id']}",
            json={"password": TENANT_PASSWORD},
            headers=mh,
        )
        token = client.post(
            f"{PLATFORM}/api/auth/login",
            json={"email": cenario["admin_email"], "password": TENANT_PASSWORD},
        ).json()["token"]
        uh = {"Authorization": f"Bearer {token}"}

        provision = client.post(f"{PLATFORM}/api/omnichannel/provision", json={}, headers=uh)
        account_id = provision.json().get("chatwoot_account_id")
        check(f"{cenario['nome']}: operação provisionada", bool(account_id), provision.text)

        templates = client.get(f"{PLATFORM}/api/templates", headers=uh).json()
        template = next((t for t in templates if t["name"] == cenario["template"]), None)
        ativo = bool(template and template.get("active_version_id"))
        if not check(f"{cenario['nome']}: template ativo", ativo):
            continue

        sufixo = uuid.uuid4().hex[:6]
        integracao = client.post(
            f"{PLATFORM}/api/integrations",
            json={"name": f"canal-{sufixo}", "channel": "api", "template_id": template["id"]},
            headers=uh,
        ).json()

        canal = client.post(
            f"{BRIDGE}/admin/channels",
            headers=bridge_headers,
            json={
                "tenant_id": usuario["tenant_id"],
                "provider": "wapi",
                "external_id": f"inst-{cenario['nome']}-{sufixo}",
                "token": "token-de-teste",
            },
        ).json()
        inbox_id = canal.get("chatwoot_inbox_id")
        check(f"{cenario['nome']}: canal e inbox", bool(inbox_id), str(canal)[:200])

        client.post(
            f"{BRIDGE}/admin/ai-config",
            headers=bridge_headers,
            json={
                "tenant_id": usuario["tenant_id"],
                "chatwoot_inbox_id": inbox_id,
                "template_id": template["id"],
                "integration_key": integracao.get("api_key"),
                "autopilot": True,
            },
        )

        bot = client.post(
            f"{CHATWOOT}/platform/api/v1/agent_bots",
            headers=platform_headers,
            json={
                "name": f"IA {cenario['nome']} {sufixo}",
                "outgoing_url": f"{BRIDGE}/agent-bot",
                "account_id": account_id,
            },
        ).json()

        agente_token = None
        for candidato in range(1, 80):
            corpo = client.get(
                f"{CHATWOOT}/platform/api/v1/users/{candidato}", headers=platform_headers
            )
            if corpo.status_code == 200 and corpo.json().get("email") == cenario["admin_email"]:
                agente_token = corpo.json()["access_token"]
                break
        if not check(f"{cenario['nome']}: usuário espelhado", bool(agente_token)):
            continue

        client.post(
            f"{CHATWOOT}/api/v1/accounts/{account_id}/inboxes/{inbox_id}/set_agent_bot",
            headers={"api_access_token": agente_token},
            json={"agent_bot": bot.get("id")},
        )

        telefone = f"5511{uuid.uuid4().int % 100000000:08d}"
        entrada = client.post(
            f"{BRIDGE}{canal['webhook_path']}",
            json={
                "phone": f"{telefone}@c.us",
                "text": cenario["pergunta"],
                "messageId": f"msg-{sufixo}",
            },
        )
        check(
            f"{cenario['nome']}: mensagem entrou na fila",
            entrada.json().get("status") == "accepted",
            entrada.text,
        )

        # A IA responde de verdade: consulta o datasource e escreve na conversa.
        resposta, conversa = "", None
        limite = time.time() + 240
        while time.time() < limite:
            conversas = client.get(
                f"{CHATWOOT}/api/v1/accounts/{account_id}/conversations",
                headers={"api_access_token": agente_token},
                params={"status": "all", "assignee_type": "all"},
            ).json()
            payload = (conversas.get("data") or {}).get("payload") or []
            atual = next((c for c in payload if str(c.get("id"))), None)
            if atual:
                conversa = atual["id"]
                mensagens = client.get(
                    f"{CHATWOOT}/api/v1/accounts/{account_id}/conversations/{conversa}/messages",
                    headers={"api_access_token": agente_token},
                ).json()
                itens = mensagens.get("payload") if isinstance(mensagens, dict) else mensagens
                saidas = [m for m in (itens or []) if m.get("message_type") == 1]
                if saidas:
                    resposta = saidas[-1].get("content") or ""
                    break
            time.sleep(6)

        if not check(f"{cenario['nome']}: a IA respondeu", bool(resposta), f"conversa={conversa}"):
            continue
        _print(f"       resposta: {resposta[:200]}")
        faltando = [t for t in cenario["espera"] if t.lower() not in resposta.lower()]
        check(
            f"{cenario['nome']}: resposta usa dados reais do negócio",
            not faltando,
            f"faltou: {faltando}",
        )

        # Atendente humano assume: a partir daí a IA não pode responder por
        # cima. É a regra que evita dois interlocutores na mesma conversa.
        client.post(
            f"{CHATWOOT}/api/v1/accounts/{account_id}/conversations/{conversa}/messages",
            headers={"api_access_token": agente_token},
            json={
                "content": "Oi, aqui é a atendente, vou assumir daqui.",
                "message_type": "outgoing",
            },
        )
        time.sleep(8)

        antes = _saidas(client, account_id, conversa, agente_token)
        client.post(
            f"{BRIDGE}{canal['webhook_path']}",
            json={
                "phone": f"{telefone}@c.us",
                "text": "e voces entregam?",
                "messageId": f"msg-{sufixo}-2",
            },
        )
        time.sleep(45)
        depois = _saidas(client, account_id, conversa, agente_token)
        check(
            f"{cenario['nome']}: IA silencia quando o humano assume",
            len(depois) == len(antes),
            f"antes={len(antes)} depois={len(depois)}",
        )

    aprovado = all(ok for _, ok, _ in checks)
    print(f"\nRESULTADO: {'APROVADO' if aprovado else 'REPROVADO'}")
    sys.exit(0 if aprovado else 1)


if __name__ == "__main__":
    main()
