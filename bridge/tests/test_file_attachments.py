"""Anexos que nao sao audio (planilha, PDF, imagem) chegam ao agente pelo Chatwoot."""

import base64

import pytest

from tests.test_audio_chatwoot import _tenant_com_config


def test_extract_file_attachments_skips_audio_and_caps():
    from app.api.agent_bot import MAX_FILE_ATTACHMENTS, _extract_file_attachments

    payload = {
        "attachments": [
            {"file_type": "audio", "data_url": "https://x/a.ogg"},
            {"file_type": "file", "data_url": ""},
            *[{"file_type": "file", "data_url": f"https://x/{i}.csv"} for i in range(9)],
        ]
    }
    found = _extract_file_attachments(payload)
    assert len(found) == MAX_FILE_ATTACHMENTS
    assert all(a["file_type"] == "file" for a in found)
    assert _extract_file_attachments({}) == []


def test_file_name_from_data_url():
    from app.api.agent_bot import _file_name

    assert _file_name({"data_url": "https://x/blobs/itens%20q3.csv?sig=1"}) == "itens q3.csv"
    assert _file_name({"data_url": "https://x/", "extension": "pdf"}) == "anexo.pdf"


@pytest.mark.integration
def test_file_without_caption_reaches_the_kernel(client, tenant_id, monkeypatch):
    from app.services import chatwoot, kernel

    _tenant_com_config(tenant_id)
    captured = {}

    async def fake_download(url):
        captured["url"] = url
        return b"item,valor\nlapis,12\n"

    async def fake_token(_user_id):
        return "t"

    async def noop(*a, **k):
        return {}

    async def fake_ask(**kwargs):
        captured["ask"] = kwargs
        return {"reply": "ok", "handoff": False, "artifacts": []}

    monkeypatch.setattr(chatwoot, "download_attachment", fake_download)
    monkeypatch.setattr(chatwoot, "user_access_token", fake_token)
    monkeypatch.setattr(chatwoot, "assign_team", noop)
    monkeypatch.setattr(chatwoot, "create_message", noop)
    monkeypatch.setattr(kernel, "ask", fake_ask)

    from app.api.agent_bot import _handle_message

    payload = {
        "conversation": {"id": 9200, "inbox_id": 11},
        "content": "",
        "attachments": [{"id": 1, "file_type": "file", "data_url": "https://cw/blobs/itens.csv"}],
    }
    import asyncio

    asyncio.run(_handle_message(tenant_id, 7, payload))
    sent = captured["ask"]["attachments"][0]
    assert sent["kind"] == "file" and sent["name"] == "itens.csv"
    assert sent["content_type"] == "text/csv"
    assert base64.b64decode(sent["data_base64"]) == b"item,valor\nlapis,12\n"
    assert captured["ask"]["message"]
