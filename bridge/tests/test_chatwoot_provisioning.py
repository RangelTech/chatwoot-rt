"""Contratos de provisionamento da conta RAtende."""

import pytest


@pytest.mark.asyncio
async def test_create_account_sets_portuguese_locale(monkeypatch):
    from app.services import chatwoot

    captured = {}

    async def fake_request(method, path, *, token, json_body=None, params=None):
        captured.update(method=method, path=path, token=token, json_body=json_body)
        return {"id": 42}

    monkeypatch.setattr(chatwoot, "_request", fake_request)
    monkeypatch.setattr(chatwoot, "_platform_token", lambda: "platform-token")

    assert await chatwoot.create_account("Empresa teste") == {"id": 42}
    assert captured == {
        "method": "POST",
        "path": "/platform/api/v1/accounts",
        "token": "platform-token",
        "json_body": {"name": "Empresa teste", "locale": "pt_BR"},
    }


@pytest.mark.asyncio
async def test_user_access_token_uses_dedicated_platform_token_action(monkeypatch):
    from app.services import chatwoot

    captured = {}

    async def fake_request(method, path, *, token, json_body=None, params=None):
        captured.update(method=method, path=path, token=token, json_body=json_body)
        return {"access_token": "test-only-token"}

    monkeypatch.setattr(chatwoot, "_request", fake_request)
    monkeypatch.setattr(chatwoot, "_platform_token", lambda: "platform-token")

    assert await chatwoot.user_access_token(18) == "test-only-token"
    assert captured == {
        "method": "POST",
        "path": "/platform/api/v1/users/18/token",
        "token": "platform-token",
        "json_body": None,
    }
