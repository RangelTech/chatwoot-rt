"""PIX/chart image artifacts reaching Chatwoot as real attachments.

Gap being closed (`chatwoot-rt/docs/decisions/0002-branding-e-planos.md`,
"O que ainda não está pronto"): `generate_pix_charge` already registers the
QR code as an artifact (`kind="image"`, same mechanism `generate_chart` uses),
but nothing on the Chatwoot side ever turned that into an actual image
message — `/v1/messages` dropped `artifact` SSE events entirely, and
`chatwoot.create_message` only knows how to send a JSON `content` body, no
attachment field. These tests cover the new `_deliver_artifacts` path in
`app/api/agent_bot.py`.
"""

import asyncio

import pytest

pytestmark = pytest.mark.integration


def _tenant_pronto(tenant_id: str) -> None:
    from app.db import get_connection

    with get_connection() as conn:
        conn.execute(
            """INSERT INTO tenant_links (tenant_id, tenant_key, tenant_name, chatwoot_account_id)
               VALUES (%s, 'loja-pix', 'Loja Pix', 7)""",
            (tenant_id,),
        )
        conn.execute(
            """INSERT INTO user_links (tenant_id, platform_user_id, email, chatwoot_user_id, role)
               VALUES (%s, gen_random_uuid(), 'dono@loja-pix.com', 3, 'administrator')""",
            (tenant_id,),
        )


def test_image_artifact_is_delivered_as_a_chatwoot_attachment(client, tenant_id, monkeypatch):
    from app.services import chatwoot, kernel, tenants

    sent_attachments = []
    sent_texts = []

    async def falso_token(_user_id):
        return "token-de-conta"

    async def falso_create_message(*args, **kwargs):
        sent_texts.append((args, kwargs))
        return {}

    async def falso_ask(**kwargs):
        return {
            "reply": "aqui está o código copia-e-cola: 000201...",
            "handoff": False,
            "artifacts": [
                {"artifact_id": "art-pix-1", "kind": "image", "title": "QR Code PIX — R$ 48.90"}
            ],
        }

    async def falso_fetch_artifact(*, integration_key, artifact_id):
        assert integration_key == "chave"
        assert artifact_id == "art-pix-1"
        return b"\x89PNGfakebytes", "image/png", "QR Code PIX — R$ 48.90.png"

    async def falso_create_message_with_attachment(
        account_id, token, conversation_id, *, file_bytes, filename, content_type, **kwargs
    ):
        sent_attachments.append(
            {
                "account_id": account_id,
                "conversation_id": conversation_id,
                "file_bytes": file_bytes,
                "filename": filename,
                "content_type": content_type,
            }
        )
        return {}

    monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
    monkeypatch.setattr(chatwoot, "create_message", falso_create_message)
    monkeypatch.setattr(
        chatwoot, "create_message_with_attachment", falso_create_message_with_attachment
    )
    monkeypatch.setattr(kernel, "ask", falso_ask)
    monkeypatch.setattr(kernel, "fetch_artifact", falso_fetch_artifact)

    _tenant_pronto(tenant_id)
    tenants.upsert_ai_config(
        tenant_id=tenant_id,
        chatwoot_inbox_id=None,
        template_id="11111111-1111-1111-1111-111111111111",
        integration_key="chave",
    )

    from app.api.agent_bot import _handle_message

    payload = {"conversation": {"id": 4001, "inbox_id": 11}, "content": "quero pagar"}
    asyncio.run(_handle_message(tenant_id, 7, payload))

    # Texto (copia-e-cola) chega como mensagem normal.
    assert len(sent_texts) == 1
    assert "copia-e-cola" in sent_texts[0][0][3]

    # QR Code chega como anexo de verdade, não como texto/JSON cru.
    assert len(sent_attachments) == 1
    attachment = sent_attachments[0]
    assert attachment["conversation_id"] == 4001
    assert attachment["file_bytes"] == b"\x89PNGfakebytes"
    assert attachment["content_type"] == "image/png"
    assert "QR Code PIX" in attachment["filename"]


def test_a_failed_artifact_fetch_does_not_lose_the_text_reply(client, tenant_id, monkeypatch):
    """Se o download do artefato falhar, o cliente ainda recebe o texto (o
    copia-e-cola já paga sozinho) — silêncio total seria pior que perder só a
    imagem."""
    from app.services import chatwoot, kernel, tenants

    sent_texts = []

    async def falso_token(_user_id):
        return "token-de-conta"

    async def falso_create_message(*args, **kwargs):
        sent_texts.append(args)
        return {}

    async def falso_ask(**kwargs):
        return {
            "reply": "código copia-e-cola: 000201...",
            "handoff": False,
            "artifacts": [{"artifact_id": "art-x", "kind": "image", "title": "QR"}],
        }

    async def falso_fetch_artifact(*, integration_key, artifact_id):
        raise kernel.KernelError("agent-platform indisponível")

    monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
    monkeypatch.setattr(chatwoot, "create_message", falso_create_message)
    monkeypatch.setattr(kernel, "ask", falso_ask)
    monkeypatch.setattr(kernel, "fetch_artifact", falso_fetch_artifact)

    _tenant_pronto(tenant_id)
    tenants.upsert_ai_config(
        tenant_id=tenant_id,
        chatwoot_inbox_id=None,
        template_id="11111111-1111-1111-1111-111111111111",
        integration_key="chave",
    )

    from app.api.agent_bot import _handle_message

    payload = {"conversation": {"id": 4002, "inbox_id": 11}, "content": "quero pagar"}
    # Não pode levantar exceção nem perder o texto por causa da falha na imagem.
    asyncio.run(_handle_message(tenant_id, 7, payload))
    assert len(sent_texts) == 1


def test_non_image_artifacts_are_not_sent_as_attachments(client, tenant_id, monkeypatch):
    """Kind != image (ex.: "file") continua com o caminho de link/download já
    existente, não deve nem tentar baixar bytes aqui."""
    from app.services import chatwoot, kernel, tenants

    fetched = []

    async def falso_token(_user_id):
        return "token-de-conta"

    async def falso_create_message(*args, **kwargs):
        return {}

    async def falso_ask(**kwargs):
        return {
            "reply": "segue o link do relatório",
            "handoff": False,
            "artifacts": [{"artifact_id": "art-file", "kind": "file", "title": "Relatório.xlsx"}],
        }

    async def falso_fetch_artifact(*, integration_key, artifact_id):
        fetched.append(artifact_id)
        return b"", "application/octet-stream", "x"

    monkeypatch.setattr(chatwoot, "user_access_token", falso_token)
    monkeypatch.setattr(chatwoot, "create_message", falso_create_message)
    monkeypatch.setattr(kernel, "ask", falso_ask)
    monkeypatch.setattr(kernel, "fetch_artifact", falso_fetch_artifact)

    _tenant_pronto(tenant_id)
    tenants.upsert_ai_config(
        tenant_id=tenant_id,
        chatwoot_inbox_id=None,
        template_id="11111111-1111-1111-1111-111111111111",
        integration_key="chave",
    )

    from app.api.agent_bot import _handle_message

    payload = {"conversation": {"id": 4003, "inbox_id": 11}, "content": "quero o relatorio"}
    asyncio.run(_handle_message(tenant_id, 7, payload))
    assert fetched == []
