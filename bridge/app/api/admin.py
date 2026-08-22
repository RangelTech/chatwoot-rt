"""Provisionamento e SSO.

Estas rotas são chamadas pelo agent-platform (máquina a máquina), nunca pelo
navegador de um cliente: quem provisiona conta e gera link de login é o
sistema mestre, com o token administrativo da ponte.
"""

import logging
import secrets

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from app.config import settings
from app.services import chatwoot, tenants

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/admin", tags=["admin"])


def require_admin(request: Request) -> None:
    """Sem token administrativo configurado, a ponte não aceita provisionar."""
    if not settings.bridge_admin_token:
        raise HTTPException(status_code=503, detail="ponte sem token administrativo configurado")
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not secrets.compare_digest(
        token, settings.bridge_admin_token
    ):
        raise HTTPException(status_code=401, detail="não autorizado")


class TenantIn(BaseModel):
    tenant_id: str
    tenant_key: str = Field(min_length=1, max_length=100)
    tenant_name: str = Field(min_length=1, max_length=200)


class UserIn(BaseModel):
    tenant_id: str
    platform_user_id: str
    email: str
    name: str = "Operador"
    role: str = Field(default="agent", pattern="^(agent|administrator)$")


class MenuDemoIn(BaseModel):
    tenant_id: str
    inbox_name: str = "Fila Demo IVR"


class AiConfigIn(BaseModel):
    tenant_id: str
    chatwoot_inbox_id: int | None = None
    template_id: str | None = None
    integration_key: str | None = None
    autopilot: bool = True
    handoff_team_id: int | None = None


class BrandingIn(BaseModel):
    tenant_id: str
    brand_name: str = Field(min_length=1, max_length=200)
    primary_color: str = Field(pattern=r"^#[0-9a-fA-F]{6}$")
    secondary_color: str = Field(pattern=r"^#[0-9a-fA-F]{6}$")
    theme: str = Field(pattern=r"^(light|dark)$")
    logo_url: str = Field(default="", max_length=2000)
    version: int = Field(ge=1)


@router.post("/tenants", dependencies=[Depends(require_admin)])
async def provision_tenant(payload: TenantIn):
    """Cria (ou reaproveita) a Account do Chatwoot do tenant. Idempotente."""
    link = tenants.upsert_tenant_link(
        tenant_id=payload.tenant_id,
        tenant_key=payload.tenant_key,
        tenant_name=payload.tenant_name,
    )
    if link["chatwoot_account_id"]:
        # Idempotente também para os Teams: cobre o provisionamento
        # retroativo (rodar de novo pra tenant que já existia antes desta
        # feature) e o caso comum de a Account já existir mas o admin ainda
        # não (ver _ensure_default_teams).
        await _ensure_default_teams(payload.tenant_id)
        await _ensure_devolver_para_ia(payload.tenant_id)
        return {
            "status": "ok",
            "chatwoot_account_id": link["chatwoot_account_id"],
            "created": False,
        }

    account = await chatwoot.create_account(payload.tenant_name)
    account_id = account.get("id")
    if not account_id:
        raise HTTPException(status_code=502, detail="Chatwoot não devolveu id da conta")
    link = tenants.set_chatwoot_account(payload.tenant_id, int(account_id))
    await _ensure_default_teams(payload.tenant_id)
    await _ensure_devolver_para_ia(payload.tenant_id)
    return {"status": "ok", "chatwoot_account_id": link["chatwoot_account_id"], "created": True}


@router.put("/branding", dependencies=[Depends(require_admin)])
async def sync_branding(payload: BrandingIn):
    """Espelha somente a cópia de consumo da marca no Chatwoot.

    Não aceita um account_id do chamador: o vínculo tenant -> Account vem da
    tabela da ponte, impedindo que um tenant escreva na conta de outro.
    """
    link = tenants.get_tenant_link(payload.tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        raise HTTPException(status_code=409, detail="tenant ainda não provisionado no RAtende")
    attrs = {
        "ragentes_branding": {
            "brand_name": payload.brand_name,
            "primary_color": payload.primary_color,
            "secondary_color": payload.secondary_color,
            "theme": payload.theme,
            "logo_url": payload.logo_url,
            "version": payload.version,
        }
    }
    await chatwoot.update_account_branding(
        int(link["chatwoot_account_id"]), name=payload.brand_name, custom_attributes=attrs
    )
    return {
        "status": "ok",
        "chatwoot_account_id": link["chatwoot_account_id"],
        "version": payload.version,
    }


async def _ensure_default_teams(tenant_id: str) -> None:
    """Cria os Teams padrão "Fila IA" e "Fila Humano" da conta, e guarda os
    dois ids na config padrão do tenant (`tenant_ai_config`, chatwoot_inbox_id
    NULL): "Fila IA" no campo novo `ai_team_id`, "Fila Humano" em
    `handoff_team_id` (já existia, usado em `_escalate`).

    Não dá pra fazer isso na criação da Account: Teams são Application API, que
    exige token de um usuário DA CONTA — e na hora que a Account nasce ainda
    não existe usuário nenhum nela (a Platform API, usada para criar a
    Account, não serve pra isso; é o mesmo motivo pelo qual o Agent Bot só é
    associado à caixa em `_garante_bot_na_caixa`, não na criação do tenant).

    Por isso este passo é best-effort e idempotente, chamado de dois lugares:
    aqui em `provision_tenant` (cobre o tenant que já tem admin quando é
    chamado de novo — inclui o provisionamento retroativo dos tenants de
    teste) e em `provision_user`, logo que o primeiro administrador ganha
    `chatwoot_user_id` (é o primeiro momento em que existe um token válido).
    Se nenhum admin existir ainda, a função não faz nada e tenta de novo na
    próxima chamada — silencioso de propósito, como o restante do
    provisionamento não-crítico desta rota.
    """
    link = tenants.get_tenant_link(tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        return

    from app.db import get_connection

    with get_connection() as conn:
        config = conn.execute(
            """SELECT ai_team_id, handoff_team_id FROM tenant_ai_config
                WHERE tenant_id = %s AND chatwoot_inbox_id IS NULL""",
            (tenant_id,),
        ).fetchone()
    ai_team_id = (config or {}).get("ai_team_id")
    humano_team_id = (config or {}).get("handoff_team_id")
    if ai_team_id and humano_team_id:
        return  # já provisionado

    admin_link = _first_admin(tenant_id)
    if admin_link is None:
        return  # sem admin ainda; a próxima chamada tenta de novo

    account_id = int(link["chatwoot_account_id"])
    try:
        token = await chatwoot.user_access_token(int(admin_link["chatwoot_user_id"]))
        if not ai_team_id:
            time_ia = await chatwoot.create_team(account_id, token, "Fila IA")
            ai_team_id = int(time_ia["id"])
        if not humano_team_id:
            time_humano = await chatwoot.create_team(account_id, token, "Fila Humano")
            humano_team_id = int(time_humano["id"])
        tenants.set_default_teams(tenant_id, ai_team_id=ai_team_id, handoff_team_id=humano_team_id)
    except chatwoot.ChatwootError as exc:
        logger.warning("falha ao criar os Teams padrão do tenant %s: %s", tenant_id, exc)


LABEL_DEVOLVER_IA = "ia-retomar"
MACRO_DEVOLVER_IA = "Devolver para IA"


async def _ensure_devolver_para_ia(tenant_id: str) -> None:
    """Registra o Webhook de CONTA (evento `conversation_updated`) e a Macro
    "Devolver para IA" — a implementação da Seção 2 do produto de filas
    IA/Humano (botão pra tirar a conversa de `human_active` e voltar pra
    `ai_active`).

    O Webhook de CONTA é mecanismo separado do Agent Bot webhook: precisa ser
    registrado à parte (`Api::V1::Accounts::WebhooksController`), com uma URL
    que já carrega um token opaco por tenant — o payload de
    `conversation_updated` não traz account_id nem o id global da conversa,
    então não dá pra identificar o tenant só pelo corpo (mesmo problema, mesma
    solução do webhook do WhatsApp não-oficial em `tenant_channels`).

    A Macro aplica a label reservada `ia-retomar` e reatribui a conversa para
    a "Fila IA" — é o botão que o atendente aperta; ver `label_webhook.py`
    para o outro lado (o bridge reagindo à label).

    Best-effort e idempotente, como `_ensure_default_teams`: sem admin
    provisionado ainda ou sem BRIDGE_PUBLIC_URL configurada, não faz nada e
    tenta de novo na próxima chamada.
    """
    if not settings.bridge_public_url:
        logger.warning(
            "BRIDGE_PUBLIC_URL não configurada — webhook/macro de 'Devolver para IA' "
            "não registrados para o tenant %s",
            tenant_id,
        )
        return

    link = tenants.get_tenant_link(tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        return
    admin_link = _first_admin(tenant_id)
    if admin_link is None:
        return  # sem admin ainda; a próxima chamada tenta de novo

    account_id = int(link["chatwoot_account_id"])
    token_url = tenants.ensure_conversation_webhook_token(tenant_id)
    webhook_url = f"{settings.bridge_public_url.rstrip('/')}/agent-bot/label/{token_url}"

    try:
        user_token = await chatwoot.user_access_token(int(admin_link["chatwoot_user_id"]))

        existentes = await chatwoot.list_account_webhooks(account_id, user_token)
        if not any(w.get("url") == webhook_url for w in existentes):
            await chatwoot.create_account_webhook(
                account_id, user_token, webhook_url, ["conversation_updated"]
            )

        macros = await chatwoot.list_macros(account_id, user_token)
        if not any(m.get("name") == MACRO_DEVOLVER_IA for m in macros):
            from app.db import get_connection

            with get_connection() as conn:
                config = conn.execute(
                    """SELECT ai_team_id FROM tenant_ai_config
                        WHERE tenant_id = %s AND chatwoot_inbox_id IS NULL""",
                    (tenant_id,),
                ).fetchone()
            actions = [{"action_name": "add_label", "action_params": [LABEL_DEVOLVER_IA]}]
            ai_team_id = (config or {}).get("ai_team_id")
            if ai_team_id:
                actions.append({"action_name": "assign_team", "action_params": [int(ai_team_id)]})
            await chatwoot.create_macro(account_id, user_token, MACRO_DEVOLVER_IA, actions)
    except chatwoot.ChatwootError as exc:
        logger.warning(
            "falha ao registrar webhook/macro de 'Devolver para IA' do tenant %s: %s",
            tenant_id,
            exc,
        )


@router.post("/users", dependencies=[Depends(require_admin)])
async def provision_user(payload: UserIn):
    """Espelha um usuário da plataforma no Chatwoot, sem pedir cadastro novo."""
    link = tenants.get_tenant_link(payload.tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        raise HTTPException(status_code=409, detail="tenant ainda não provisionado")

    user_link = tenants.upsert_user_link(
        tenant_id=payload.tenant_id,
        platform_user_id=payload.platform_user_id,
        email=payload.email,
        role=payload.role,
    )
    if user_link["chatwoot_user_id"]:
        return {"status": "ok", "chatwoot_user_id": user_link["chatwoot_user_id"], "created": False}

    # Senha aleatória: o acesso é sempre por login-link, nunca digitada. O
    # sufixo cobre a política do Chatwoot, que exige caractere especial.
    password = f"{secrets.token_urlsafe(24)}#Aa1!"
    user = await chatwoot.create_user(payload.name, payload.email, password)
    user_id = user.get("id")
    if not user_id:
        raise HTTPException(status_code=502, detail="Chatwoot não devolveu id do usuário")
    await chatwoot.add_account_user(int(link["chatwoot_account_id"]), int(user_id), payload.role)
    user_link = tenants.set_chatwoot_user(str(user_link["id"]), int(user_id))
    if payload.role == "administrator":
        # Primeiro admin com token: é o primeiro momento em que dá pra criar
        # os Teams padrão (ver _ensure_default_teams). Tenant sem admin
        # nenhum ainda fica só com a Account, sem fila — normal, é retomado
        # quando o admin for provisionado.
        await _ensure_default_teams(payload.tenant_id)
        await _ensure_devolver_para_ia(payload.tenant_id)
    return {"status": "ok", "chatwoot_user_id": user_link["chatwoot_user_id"], "created": True}


@router.get("/sso/{tenant_id}/{platform_user_id}", dependencies=[Depends(require_admin)])
async def sso_link(tenant_id: str, platform_user_id: str):
    """URL temporária de login no Chatwoot para um usuário já provisionado."""
    user_link = tenants.get_user_link(tenant_id, platform_user_id)
    if user_link is None or not user_link["chatwoot_user_id"]:
        raise HTTPException(status_code=404, detail="usuário não provisionado no Chatwoot")
    url = await chatwoot.login_link(int(user_link["chatwoot_user_id"]))
    return {"url": url}


@router.post("/logout/{tenant_id}/{platform_user_id}", dependencies=[Depends(require_admin)])
async def sso_logout(tenant_id: str, platform_user_id: str):
    """Derruba a sessão do usuário no Chatwoot (produto-05 seção 6c) — par
    de /sso: chamado no logout do RAgentes pra sincronizar o RAtende.
    Idempotente: usuário nunca provisionado no Chatwoot não é erro, é no-op
    (nada pra derrubar)."""
    user_link = tenants.get_user_link(tenant_id, platform_user_id)
    if user_link is None or not user_link["chatwoot_user_id"]:
        return {"status": "noop", "detail": "usuário não provisionado no Chatwoot"}
    await chatwoot.logout_user(int(user_link["chatwoot_user_id"]))
    return {"status": "ok"}


@router.post("/menu-demo", dependencies=[Depends(require_admin)])
async def provision_menu_demo(payload: MenuDemoIn):
    """Produto-08: cria (idempotente) a inbox + o Team "Fila Demo IVR" e liga
    o Agent Bot nela — feature OPCIONAL por tenant, nunca automática (não faz
    parte de `provision_tenant`/`_ensure_default_teams`, que continuam só
    criando "Fila IA"/"Fila Humano").

    A inbox criada aqui é de canal `api`, igual às de `provision_channel`,
    mas SEM registro em `tenant_channels` — ela não representa um canal
    externo real (WhatsApp/Instagram), é só a superfície onde o Agent Bot
    webhook vai bater. Quem entra em contato com ela hoje é só o teste
    end-to-end (Application API cria a conversa direto na inbox).

    O que garante isolamento do fluxo de IA não é este endpoint, e sim o
    branch em `agent_bot.py`: a config gravada em `menu_bot_config` nunca é
    lida por `ai_config_for`/`_handle_message`.
    """
    link = tenants.get_tenant_link(payload.tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        raise HTTPException(status_code=409, detail="tenant ainda não provisionado")
    admin_link = _first_admin(payload.tenant_id)
    if admin_link is None:
        raise HTTPException(status_code=409, detail="tenant sem usuário administrador provisionado")

    account_id = int(link["chatwoot_account_id"])
    token = await chatwoot.user_access_token(int(admin_link["chatwoot_user_id"]))

    from app.db import get_connection

    with get_connection() as conn:
        existente = conn.execute(
            "SELECT * FROM menu_bot_config WHERE tenant_id = %s", (payload.tenant_id,)
        ).fetchone()

    if existente:
        return {
            "status": "ok",
            "created": False,
            "chatwoot_inbox_id": existente["chatwoot_inbox_id"],
        }

    inboxes = await chatwoot.list_inboxes(account_id, token)
    inbox = next((i for i in inboxes if i.get("name") == payload.inbox_name), None)
    if inbox is None:
        inbox = await chatwoot.create_api_inbox(
            account_id,
            token,
            name=payload.inbox_name,
            # A fila demo não fala com nenhum provedor externo — não existe
            # "resposta de saída" real, o outbound daqui é sempre
            # `chatwoot.create_message` chamado de dentro do próprio bridge.
            webhook_url="",
        )
    inbox_id = int(inbox["id"])

    bot_id = link["chatwoot_agent_bot_id"]
    if not bot_id:
        bot = await chatwoot.create_agent_bot(
            account_id,
            name=f"IA {link['tenant_name'] or link['tenant_key']}".strip()[:60],
            outgoing_url=f"{settings.bridge_public_url.rstrip('/')}/agent-bot",
        )
        bot_id = int(bot["id"])
        tenants.set_agent_bot_id(payload.tenant_id, bot_id)
    await chatwoot.set_agent_bot(account_id, token, inbox_id, int(bot_id))

    macros_needed = [
        ("Vendas Demo", "team_vendas_id"),
        ("Suporte Demo", "team_suporte_id"),
        ("Financeiro Demo", "team_financeiro_id"),
    ]
    team_ids: dict[str, int] = {}
    for nome, campo in macros_needed:
        team = await chatwoot.create_team(account_id, token, nome)
        team_ids[campo] = int(team["id"])

    config = tenants.upsert_menu_bot_config(
        tenant_id=payload.tenant_id,
        chatwoot_inbox_id=inbox_id,
        **team_ids,
    )
    return {
        "status": "ok",
        "created": True,
        "chatwoot_inbox_id": inbox_id,
        "team_ids": team_ids,
        "config_id": str(config["id"]),
    }


@router.post("/ai-config", dependencies=[Depends(require_admin)])
async def set_ai_config(payload: AiConfigIn):
    config = tenants.upsert_ai_config(
        tenant_id=payload.tenant_id,
        chatwoot_inbox_id=payload.chatwoot_inbox_id,
        template_id=payload.template_id,
        integration_key=payload.integration_key,
        autopilot=payload.autopilot,
        handoff_team_id=payload.handoff_team_id,
    )
    bot = await _garante_bot_na_caixa(
        payload.tenant_id,
        payload.chatwoot_inbox_id,
        ligado=bool(payload.template_id and payload.autopilot),
    )
    return {
        "status": "ok",
        "autopilot": config["autopilot"],
        "has_integration_key": bool(config["integration_key_encrypted"]),
        "agent_bot": bot,
    }


async def _garante_bot_na_caixa(tenant_id: str, inbox_id: int | None, *, ligado: bool) -> str:
    """Associa (ou desassocia) o Agent Bot da conta nesta caixa.

    Escolher o agente na tela não basta: o Chatwoot só avisa a ponte de uma
    mensagem se houver um Agent Bot associado ÀQUELA caixa. A ponte fazia isso
    apenas nas caixas que ela mesma criava (W-API) — e o desenho da instalação é
    o oposto: o cliente conecta Instagram, Messenger ou WhatsApp oficial dentro
    do Chatwoot, e essas caixas nasciam sem bot. O sintoma é o pior possível:
    agente configurado, cliente escrevendo, silêncio, e nenhum erro em lugar
    nenhum.

    Falhar aqui não desfaz a configuração — ela é válida e o vínculo pode ser
    refeito. Por isso o erro vira estado devolvido, não exceção.
    """
    if inbox_id is None:
        return "sem caixa (config padrão do tenant)"

    link = tenants.get_tenant_link(tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        return "tenant sem conta no Chatwoot"
    admin_link = _first_admin(tenant_id)
    if admin_link is None:
        return "tenant sem usuário provisionado"

    account_id = int(link["chatwoot_account_id"])
    try:
        token = await chatwoot.user_access_token(int(admin_link["chatwoot_user_id"]))
        bot_id = link["chatwoot_agent_bot_id"]
        if ligado and not bot_id:
            # Um bot por conta: o Chatwoot não deduplica por nome, e criar um a
            # cada vinculação encheria a conta de bots órfãos.
            bot = await chatwoot.create_agent_bot(
                account_id,
                name=f"IA {link['tenant_name'] or link['tenant_key']}".strip()[:60],
                outgoing_url=f"{settings.bridge_public_url.rstrip('/')}/agent-bot",
            )
            bot_id = int(bot["id"])
            tenants.set_agent_bot_id(tenant_id, bot_id)
        if ligado and bot_id:
            await chatwoot.set_agent_bot(account_id, token, inbox_id, int(bot_id))
            return "ligado"
        if not ligado and bot_id:
            await chatwoot.set_agent_bot(account_id, token, inbox_id, None)
            return "desligado"
        return "sem bot"
    except chatwoot.ChatwootError as exc:
        logger.warning("falha ao associar o Agent Bot na inbox %s: %s", inbox_id, exc)
        return f"erro: {exc}"


def _first_admin(tenant_id: str) -> dict | None:
    from app.db import get_connection

    with get_connection() as conn:
        return conn.execute(
            """SELECT * FROM user_links
                WHERE tenant_id = %s AND chatwoot_user_id IS NOT NULL
                ORDER BY (role = 'administrator') DESC, created_at
                LIMIT 1""",
            (tenant_id,),
        ).fetchone()


@router.get("/ai-config/{tenant_id}", dependencies=[Depends(require_admin)])
async def list_ai_config(tenant_id: str):
    """Caixas do tenant e qual template atende cada uma.

    Um tenant tem várias caixas — WhatsApp, Instagram, site — e cada uma pode
    ser atendida por um agente diferente. A configuração por caixa já existia no
    banco; faltava alguém conseguir ver e escolher sem chamar a API na unha.

    A lista vem do Chatwoot, não da ponte: caixa criada dentro do próprio
    Chatwoot (um Instagram conectado pela tela) não passa por aqui, e é
    exatamente onde alguém vai querer ligar a IA.
    """
    link = tenants.get_tenant_link(tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        raise HTTPException(status_code=404, detail="tenant sem conta no Chatwoot")

    admin_link = _first_admin(tenant_id)
    if admin_link is None:
        raise HTTPException(status_code=409, detail="tenant sem usuário provisionado")

    token = await chatwoot.user_access_token(int(admin_link["chatwoot_user_id"]))
    caixas = await chatwoot.list_inboxes(int(link["chatwoot_account_id"]), token)

    from app.db import get_connection

    with get_connection() as conn:
        configs = conn.execute(
            "SELECT * FROM tenant_ai_config WHERE tenant_id = %s", (tenant_id,)
        ).fetchall()
    por_inbox = {c["chatwoot_inbox_id"]: c for c in configs}
    # Config com inbox NULL é o padrão do tenant: vale para caixa que ninguém
    # configurou. Mostrá-la como "herdado" evita a leitura errada de que a caixa
    # está sem IA quando ela na verdade cai no padrão.
    padrao = por_inbox.get(None)

    return {
        "default": _ai_config_out(padrao) if padrao else None,
        "inboxes": [
            {
                "chatwoot_inbox_id": int(caixa["id"]),
                "name": caixa.get("name", ""),
                "channel_type": caixa.get("channel_type", ""),
                "ai": _ai_config_out(por_inbox.get(int(caixa["id"]))),
                "inherits_default": int(caixa["id"]) not in por_inbox and padrao is not None,
            }
            for caixa in caixas
        ],
    }


def _ai_config_out(config: dict | None) -> dict | None:
    if config is None:
        return None
    return {
        "template_id": str(config["template_id"]) if config["template_id"] else None,
        "autopilot": config["autopilot"],
        "handoff_team_id": config["handoff_team_id"],
        "ai_team_id": config["ai_team_id"],
        # A chave nunca volta: o que interessa a quem lê é se existe.
        "has_integration_key": bool(config["integration_key_encrypted"]),
    }
