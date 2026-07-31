"""Smoke fim a fim da camada omnichannel, contra ambientes reais.

Prova, sem mockar nada, o caminho completo:

    provisiona tenant -> espelha usuário -> cria canal e inbox ->
    simula mensagem do provedor -> Chatwoot registra a conversa ->
    Agent Bot chama o kernel -> a resposta da IA volta para a conversa

Uso:
    BRIDGE_URL=... BRIDGE_ADMIN_TOKEN=... CHATWOOT_URL=... \
    CHATWOOT_PLATFORM_TOKEN=... AGENT_PLATFORM_URL=... \
    HOMOLOG_MASTER_EMAIL=... HOMOLOG_MASTER_PASSWORD=... \
    python scripts/smoke/omnichannel_e2e.py
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

SUFFIX = uuid.uuid4().hex[:6]
# Telefone precisa ser E.164 de verdade: o Chatwoot valida.
PHONE = f"5511{uuid.uuid4().int % 100000000:08d}"
checks: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> bool:
    checks.append((name, ok, detail))
    suffix = f" — {detail[:160]}" if detail and not ok else ""
    print(f"  [{'ok ' if ok else 'FAIL'}] {name}{suffix}")
    return ok


def main() -> None:
    client = httpx.Client(timeout=180.0)
    bridge_headers = {"Authorization": f"Bearer {BRIDGE_TOKEN}", "Content-Type": "application/json"}
    platform_headers = {"api_access_token": PLATFORM_TOKEN}

    print(f"=== smoke omnichannel ({SUFFIX}) ===")

    # 1. Empresa e usuário administrador no agent-platform.
    master = client.post(
        f"{PLATFORM}/api/auth/login",
        json={"email": MASTER_EMAIL, "password": MASTER_PASSWORD},
    ).json()["token"]
    mh = {"Authorization": f"Bearer {master}"}
    tenant = client.post(
        f"{PLATFORM}/api/tenants",
        json={"name": f"Omni E2E {SUFFIX}", "tenant_key": f"omni-e2e-{SUFFIX}"},
        headers=mh,
    ).json()
    profiles = client.get(
        f"{PLATFORM}/api/user-profiles?tenant_id={tenant['id']}", headers=mh
    ).json()
    admin_profile = next(
        p for p in profiles if p.get("tenant_id") == tenant["id"] and p["name"] == "Administrador"
    )
    email = f"omni-e2e-{SUFFIX}@example.com"
    client.post(
        f"{PLATFORM}/api/users",
        json={
            "email": email,
            "name": "Operador E2E",
            "password": "senha-forte-123",
            "tenant_id": tenant["id"],
            "profile_id": admin_profile["id"],
        },
        headers=mh,
    )
    user_token = client.post(
        f"{PLATFORM}/api/auth/login", json={"email": email, "password": "senha-forte-123"}
    ).json()["token"]
    uh = {"Authorization": f"Bearer {user_token}"}

    # 2. Provisionamento e SSO, pelo caminho que o usuário real usa.
    provision = client.post(f"{PLATFORM}/api/omnichannel/provision", json={}, headers=uh)
    account_id = provision.json().get("chatwoot_account_id")
    check("provisiona a conta do Chatwoot", provision.status_code == 200, provision.text)
    sso = client.get(f"{PLATFORM}/api/omnichannel/sso", headers=uh)
    check("gera link de SSO", sso.status_code == 200 and "sso_auth_token" in sso.text, sso.text)

    # 3. Chave de integração: é ela que dá template/modelo/tools ao agente.
    integration = client.post(
        f"{PLATFORM}/api/integrations",
        json={"name": f"omni-{SUFFIX}", "channel": "api"},
        headers=uh,
    ).json()
    api_key = integration.get("api_key")
    check("cria chave de integração", bool(api_key))

    # 4. Canal + inbox de API.
    channel = client.post(
        f"{BRIDGE}/admin/channels",
        headers=bridge_headers,
        json={
            "tenant_id": tenant["id"],
            "provider": "wapi",
            "external_id": f"inst-{SUFFIX}",
            "token": "token-de-teste",
        },
    ).json()
    inbox_id = channel.get("chatwoot_inbox_id")
    check("cria canal e inbox", bool(inbox_id), str(channel))

    client.post(
        f"{BRIDGE}/admin/ai-config",
        headers=bridge_headers,
        json={
            "tenant_id": tenant["id"],
            "chatwoot_inbox_id": inbox_id,
            "integration_key": api_key,
            "autopilot": True,
        },
    )

    # 5. Agent Bot apontando para a ponte, associado à inbox do tenant.
    bot = client.post(
        f"{CHATWOOT}/platform/api/v1/agent_bots",
        headers=platform_headers,
        json={
            "name": f"Agente IA {SUFFIX}",
            "outgoing_url": f"{BRIDGE}/agent-bot",
            "account_id": account_id,
        },
    ).json()
    check("cria agent bot", bool(bot.get("id")), str(bot)[:200])

    account_user_token = None
    for candidate in range(1, 60):
        body = client.get(
            f"{CHATWOOT}/platform/api/v1/users/{candidate}", headers=platform_headers
        )
        if body.status_code == 200 and body.json().get("email") == email:
            account_user_token = body.json()["access_token"]
            break
    check("encontra o usuário espelhado", bool(account_user_token), f"account={account_id}")

    if account_user_token and bot.get("id"):
        assign = client.post(
            f"{CHATWOOT}/api/v1/accounts/{account_id}/inboxes/{inbox_id}/set_agent_bot",
            headers={"api_access_token": account_user_token},
            json={"agent_bot": bot["id"]},
        )
        check("associa o bot à inbox", assign.status_code < 400, assign.text[:200])

    # 6. Mensagem chegando do provedor.
    webhook = client.post(
        f"{BRIDGE}{channel['webhook_path']}",
        json={
            "phone": f"{PHONE}@c.us",
            "text": "olá, isso é um teste automatizado",
            "messageId": f"msg-{SUFFIX}",
        },
    )
    check("aceita o webhook do provedor", webhook.json().get("status") == "accepted", webhook.text)

    duplicate = client.post(
        f"{BRIDGE}{channel['webhook_path']}",
        json={
            "phone": f"{PHONE}@c.us",
            "text": "olá, isso é um teste automatizado",
            "messageId": f"msg-{SUFFIX}",
        },
    )
    check(
        "ignora reenvio do mesmo evento",
        duplicate.json().get("status") == "duplicate_ignored",
        duplicate.text,
    )

    # 7. A conversa aparece no Chatwoot e a IA responde.
    conversation_id, replied = None, False
    deadline = time.time() + 120
    while time.time() < deadline:
        conversations = client.get(
            f"{CHATWOOT}/api/v1/accounts/{account_id}/conversations",
            headers={"api_access_token": account_user_token},
        ).json()
        payload = (conversations.get("data") or {}).get("payload") or []
        if payload:
            conversation_id = payload[0]["id"]
            messages = client.get(
                f"{CHATWOOT}/api/v1/accounts/{account_id}/conversations/{conversation_id}/messages",
                headers={"api_access_token": account_user_token},
            ).json()
            items = messages.get("payload") if isinstance(messages, dict) else messages
            # message_type 1 = outgoing: veio da IA de volta para a conversa.
            if any(m.get("message_type") == 1 for m in (items or [])):
                replied = True
                break
        time.sleep(5)

    check("registra a conversa no Chatwoot", conversation_id is not None)
    check("a IA responde na conversa", replied, f"conversation={conversation_id}")

    passed = all(ok for _, ok, _ in checks)
    print(f"\nRESULTADO: {'APROVADO' if passed else 'REPROVADO'}")
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
