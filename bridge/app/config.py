"""Configuração da ponte.

Tudo que é segredo vem do ambiente (Secret Manager em produção). Nada de
credencial de tenant aqui: essa mora no banco, cifrada, e é resolvida por
tenant a cada requisição.
"""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql://bridge:bridge@localhost:5432/chatwoot_bridge"
    port: int = 8100
    db_connect_timeout: int = 5
    # "production" trava o boot sem ENCRYPTION_KEY (ver main.py); qualquer
    # outro valor (default de dev/teste) mantém a chave derivada com aviso.
    environment: str = "development"

    # Chatwoot
    chatwoot_base_url: str = "http://localhost:3000"
    # Token da Platform API — cria contas/usuários e gera o link de SSO.
    chatwoot_platform_token: str = ""

    # agent-platform (sistema mestre): identidade, tenants e kernel de IA.
    agent_platform_url: str = ""

    # Chave mestra Fernet para credenciais de canal em repouso.
    encryption_key: str = ""

    # Segredo compartilhado que autentica chamadas administrativas na ponte.
    bridge_admin_token: str = ""
    # URL pública da própria ponte: é o que o Chatwoot chama quando alguém
    # responde uma conversa, para a mensagem voltar ao canal do cliente.
    bridge_public_url: str = ""

    # Provisionamento privilegiado de instâncias Evolution na VPS (produto-05
    # seção 4, QR automático). A ponte é o único lugar que sabe SSH na VPS —
    # nem o navegador do tenant, nem o Chatwoot Rails, têm essa credencial.
    evolution_ssh_host: str = "66.94.101.153"
    evolution_ssh_user: str = "deploy"
    # Chave privada em texto (conteúdo do arquivo PEM), vinda do Secret
    # Manager em produção -- nunca um caminho de arquivo committado.
    evolution_ssh_private_key: str = ""
    evolution_domain: str = "evolution.rangeltech.net"
    evolution_image: str = "evoapicloud/evolution-api:v2.3.7"
    evolution_internal_network: str = "internal"
    evolution_public_network: str = "public"

    # Fase F: rotas internas do Luar (Rails) que dizem quem responde a conversa.
    rt_internal_url: str = ""
    rt_internal_token: str = ""

    # --- Fase CH: gateway de canais nao oficiais ---
    # Token que o Rails (chatwoot-rt) apresenta ao gateway (rede interna).
    channels_gateway_token: str = ""
    # Dominio do homeserver (Synapse privado) e tokens do appservice proprio.
    matrix_server_name: str = "matrix.internal"
    matrix_homeserver_url: str = "http://synapse:8008"
    matrix_as_token: str = ""
    matrix_hs_token: str = ""
    # Bridges (API de provisionamento do mautrix bridgev2) e segredos.
    bridge_instagram_url: str = "http://mautrix-instagram:29319"
    bridge_messenger_url: str = "http://mautrix-meta:29319"
    bridge_whatsapp_url: str = "http://mautrix-whatsapp:29318"
    bridge_provisioning_secret: str = ""
    # Limites de login (evitam bloqueio de conta): por identificador e por tenant.
    channels_login_attempts_per_hour: int = 5
    channels_login_attempts_per_tenant_hour: int = 20
    channels_webhook_max_attempts: int = 8
    channels_webhook_tolerance_s: int = 300
    # TikTok: worker por conta. "" = desligado; "fake" = simulador; "relttk" = subprocesso real;
    # "docker" = um container por conta (exige proxy de socket restrito, ver stacks/canais).
    tiktok_launcher: str = ""
    tiktok_sessions_dir: str = "/var/lib/luar/tiktok-sessions"
    tiktok_worker_image: str = ""
    tiktok_host_sessions: str = ""
    tiktok_network: str = "canais_net"
    # QA/CDP: passos de login deterministicos, sem rede e sem conta real. NUNCA em producao real.
    channels_simulator: bool = False
    channels_sim_scan_after_s: float = 20.0
    channels_sim_approve_after_s: float = 8.0

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
