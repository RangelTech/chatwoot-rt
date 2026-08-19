"""Áudio via Chatwoot (qa-02 seção 3b): antes desta ligação, uma nota de voz
sem legenda tinha `content` vazio e `_handle_message` devolvia cedo — a IA
nunca via o áudio. Cobre: extração do anexo do payload real do webhook,
download+empacotamento pro `kernel.ask`, e o fallback quando o download falha.
"""

import base64

import pytest

pytestmark = pytest.mark.integration


def _tenant_com_config(tenant_id: str, *, ai_team_id: int = 555) -> None:
    from app.services import tenants

    tenants.upsert_tenant_link(tenant_id=tenant_id, tenant_key="loja", tenant_name="Loja")
    tenants.set_chatwoot_account(tenant_id, 7)
    tenants.upsert_ai_config(
        tenant_id=tenant_id,
        chatwoot_inbox_id=None,
        template_id="11111111-1111-1111-1111-111111111111",
        integration_key="chave",
    )
    tenants.set_default_teams(tenant_id, ai_team_id=ai_team_id, handoff_team_id=666)
    from app.db import get_connection

    with get_connection() as conn:
        conn.execute(
            """INSERT INTO user_links (tenant_id, platform_user_id, email, chatwoot_user_id, role)
               VALUES (%s, gen_random_uuid(), 'dono@loja.com', 3, 'administrator')""",
            (tenant_id,),
        )


def test_extract_audio_attachment_reads_the_real_chatwoot_shape():
    from app.api.agent_bot import _extract_audio_attachment

    # Formato real do webhook `message_created`: `attachments` é irmão de
    # `content`, cada item carrega `file_type` + `data_url`.
    payload = {
        "content": "",
        "attachments": [
            {
                "id": 42,
                "message_id": 900,
                "file_type": "audio",
                "extension": None,
                "data_url": "https://chatwoot.rangeltech.net/rails/active_storage/blobs/x/nota.ogg",
            }
        ],
    }
    found = _extract_audio_attachment(payload)
    assert found is not None
    assert found["data_url"].endswith("nota.ogg")

    assert _extract_audio_attachment({"content": "oi", "attachments": []}) is None
    assert _extract_audio_attachment({"content": "oi"}) is None
    # Anexo de imagem não é confundido com áudio.
    assert (
        _extract_audio_attachment(
            {"attachments": [{"file_type": "image", "data_url": "https://x/foto.jpg"}]}
        )
        is None
    )


@pytest.mark.parametrize(
    "attachment,expected_suffix,expected_content_type",
    [
        ({"extension": "ogg", "data_url": "https://x/a"}, ".ogg", "audio/ogg"),
        ({"extension": None, "data_url": "https://x/nota.ogg"}, ".ogg", "audio/ogg"),
        ({"extension": None, "data_url": "https://x/blob-sem-extensao"}, ".ogg", "audio/ogg"),
        ({"extension": "m4a", "data_url": "https://x/a"}, ".m4a", "audio/mp4"),
    ],
)
def test_audio_filename_and_content_type_resolution(
    attachment, expected_suffix, expected_content_type
):
    from app.api.agent_bot import _AUDIO_CONTENT_TYPES, _audio_filename

    filename = _audio_filename(attachment)
    assert filename.endswith(expected_suffix)
    extension = filename.rsplit(".", 1)[-1]
    assert _AUDIO_CONTENT_TYPES.get(extension, "audio/ogg") == expected_content_type


def test_voice_note_without_caption_reaches_the_kernel_with_the_attachment(
    client, tenant_id, monkeypatch
):
    """The case this ticket exists for: WhatsApp voice note, no text typed.
    Before the fix, `content` was empty and `_handle_message` returned before
    ever calling the kernel — the message was silently dropped."""
    from app.services import chatwoot, kernel

    _tenant_com_config(tenant_id)

    audio_bytes = b"OggS fake opus payload for a whatsapp voice note"
    captured = {}

    async def fake_download(url):
        captured["downloaded_url"] = url
        return audio_bytes

    async def fake_token(_user_id):
        return "token-de-conta"

    async def fake_assign_team(*args, **kwargs):
        return {}

    async def fake_create_message(*args, **kwargs):
        return {}

    async def fake_ask(**kwargs):
        captured["ask_kwargs"] = kwargs
        return {"reply": "entendi seu áudio", "handoff": False, "artifacts": []}

    monkeypatch.setattr(chatwoot, "download_attachment", fake_download)
    monkeypatch.setattr(chatwoot, "user_access_token", fake_token)
    monkeypatch.setattr(chatwoot, "assign_team", fake_assign_team)
    monkeypatch.setattr(chatwoot, "create_message", fake_create_message)
    monkeypatch.setattr(kernel, "ask", fake_ask)

    from app.api.agent_bot import _handle_message

    payload = {
        "conversation": {"id": 9100, "inbox_id": 11},
        "content": "",
        "attachments": [
            {
                "id": 1,
                "file_type": "audio",
                "extension": "ogg",
                "data_url": "https://chatwoot.example/blobs/nota.ogg",
            }
        ],
    }
    import asyncio

    asyncio.run(_handle_message(tenant_id, 7, payload))

    assert captured["downloaded_url"] == "https://chatwoot.example/blobs/nota.ogg"
    ask_kwargs = captured["ask_kwargs"]
    assert ask_kwargs["message"]  # never empty, RunRequest/PublicMessageIn need it
    attachments = ask_kwargs["attachments"]
    assert attachments and len(attachments) == 1
    sent = attachments[0]
    assert sent["kind"] == "audio"
    assert sent["content_type"] == "audio/ogg"
    assert base64.b64decode(sent["data_base64"]) == audio_bytes


def test_text_message_is_unaffected_no_attachments_sent(client, tenant_id, monkeypatch):
    """Regression guard: a normal text message must not suddenly carry an
    `attachments` key (kernel.ask defaults it to None when absent)."""
    from app.services import chatwoot, kernel

    _tenant_com_config(tenant_id)
    captured = {}

    async def fake_token(_user_id):
        return "token-de-conta"

    async def fake_assign_team(*args, **kwargs):
        return {}

    async def fake_create_message(*args, **kwargs):
        return {}

    async def fake_ask(**kwargs):
        captured["ask_kwargs"] = kwargs
        return {"reply": "oi!", "handoff": False, "artifacts": []}

    monkeypatch.setattr(chatwoot, "user_access_token", fake_token)
    monkeypatch.setattr(chatwoot, "assign_team", fake_assign_team)
    monkeypatch.setattr(chatwoot, "create_message", fake_create_message)
    monkeypatch.setattr(kernel, "ask", fake_ask)

    from app.api.agent_bot import _handle_message

    asyncio_run_payload = {"conversation": {"id": 9200, "inbox_id": 11}, "content": "oi"}
    import asyncio

    asyncio.run(_handle_message(tenant_id, 7, asyncio_run_payload))

    assert captured["ask_kwargs"]["message"] == "oi"
    assert captured["ask_kwargs"]["attachments"] is None


def test_download_failure_falls_back_to_a_placeholder_instead_of_crashing(
    client, tenant_id, monkeypatch
):
    """A falha de rede/URL expirada não pode derrubar o `BackgroundTasks` nem
    deixar a conversa muda: a IA recebe um texto explicando o que houve."""
    from app.services import chatwoot, kernel

    _tenant_com_config(tenant_id)
    captured = {}

    async def failing_download(url):
        raise chatwoot.ChatwootError("download do anexo respondeu 404")

    async def fake_token(_user_id):
        return "token-de-conta"

    async def fake_assign_team(*args, **kwargs):
        return {}

    async def fake_create_message(*args, **kwargs):
        return {}

    async def fake_ask(**kwargs):
        captured["ask_kwargs"] = kwargs
        return {"reply": "ok", "handoff": False, "artifacts": []}

    monkeypatch.setattr(chatwoot, "download_attachment", failing_download)
    monkeypatch.setattr(chatwoot, "user_access_token", fake_token)
    monkeypatch.setattr(chatwoot, "assign_team", fake_assign_team)
    monkeypatch.setattr(chatwoot, "create_message", fake_create_message)
    monkeypatch.setattr(kernel, "ask", fake_ask)

    from app.api.agent_bot import _handle_message

    payload = {
        "conversation": {"id": 9300, "inbox_id": 11},
        "content": "",
        "attachments": [
            {"id": 1, "file_type": "audio", "data_url": "https://chatwoot.example/blobs/gone.ogg"}
        ],
    }
    import asyncio

    asyncio.run(_handle_message(tenant_id, 7, payload))

    ask_kwargs = captured["ask_kwargs"]
    assert ask_kwargs["attachments"] is None
    assert "áudio" in ask_kwargs["message"]
