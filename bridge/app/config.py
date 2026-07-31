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

    # Chatwoot
    chatwoot_base_url: str = "http://localhost:3000"
    # Token da Platform API — cria contas/usuários e gera o link de SSO.
    chatwoot_platform_token: str = ""

    # agent-platform (sistema mestre): identidade, tenants e kernel de IA.
    agent_platform_url: str = ""
    # Chave de serviço usada nas chamadas máquina-a-máquina para a plataforma.
    agent_platform_api_key: str = ""

    # Chave mestra Fernet para credenciais de canal em repouso.
    encryption_key: str = ""

    # Segredo compartilhado que autentica chamadas administrativas na ponte.
    bridge_admin_token: str = ""
    # URL pública da própria ponte: é o que o Chatwoot chama quando alguém
    # responde uma conversa, para a mensagem voltar ao canal do cliente.
    bridge_public_url: str = ""

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
