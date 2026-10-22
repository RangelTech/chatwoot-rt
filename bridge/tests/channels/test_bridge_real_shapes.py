"""Passos no formato REAL do mautrix v26.10 (capturados no smoke local de 21/10/2026).

O bridge de verdade nao devolve HTTP 4xx para senha/codigo errado: repete o passo (ou abre um
dialogo `...caa.dialog` com "Try again") com o motivo em `instructions`. Estes testes fixam isso.
"""

import json

import httpx
import pytest
from app.channels.models import ConnectionCtx
from app.channels.providers.matrix_bridge import MatrixBridgeAdapter, translate_step
from app.channels.provisioning import ProvisioningClient
from app.channels.states import State

IG_CRED = {
    "login_id": "p1",
    "type": "user_input",
    "step_id": "fi.mau.meta.instagram.credentials",
    "txn_id": "t",
    "instructions": "Enter your Instagram email or username and password.",
    "user_input": {
        "fields": [
            {"type": "username", "id": "username", "name": "Email or username", "description": ""},
            {"type": "password", "id": "password", "name": "Password", "description": ""},
        ],
        "attachments": None,
    },
}
DIALOG = {
    "login_id": "p1",
    "type": "user_input",
    "step_id": "fi.mau.meta.instagram.caa.dialog",
    "txn_id": "t",
    "instructions": "Can't find account\n\nWe can't find an account with x. Try another number or email.",
    "user_input": {
        "fields": [
            {
                "type": "select",
                "id": "dialog_action",
                "name": "Continue login",
                "default_value": "Sign up",
                "options": ["Sign up", "Try again"],
            }
        ],
        "attachments": None,
    },
}
CAPTCHA = {
    "login_id": "p1",
    "type": "user_input",
    "step_id": "fi.mau.meta.instagram.caa.captcha",
    "instructions": "Type the characters you see",
    "user_input": {
        "fields": [{"type": "captcha_code", "id": "captcha_code", "name": "Captcha code"}],
        "attachments": [
            {
                "type": "m.image",
                "filename": "captcha.png",
                "content": "iVBORw0KGgo=",
                "info": {"mimetype": "image/png", "w": 280, "h": 70},
            },
            {
                "type": "m.audio",
                "filename": "captcha.ogg",
                "content": "T2dnUw==",
                "info": {"mimetype": "audio/ogg"},
            },
        ],
    },
}
MFA_CHOICE = {
    "login_id": "p1",
    "type": "user_input",
    "step_id": "fi.mau.meta.instagram.caa.mfa_type",
    "instructions": "Choose where to receive an MFA code",
    "user_input": {
        "fields": [
            {
                "type": "select",
                "id": "mfatype",
                "name": "Login method",
                "options": ["SMS", "WhatsApp"],
            }
        ]
    },
}
OTP = {
    "login_id": "p1",
    "type": "user_input",
    "step_id": "fi.mau.meta.instagram.caa.otp_code",
    "instructions": "Enter the security code Instagram sent you",
    "user_input": {
        "fields": [{"type": "2fa_code", "id": "otp_code", "name": "Instagram verification code"}]
    },
}
OTP_AGAIN = {
    **OTP,
    "instructions": "That code is incorrect. Enter the security code Instagram sent you",
}
COMPLETE = {
    "login_id": "p1",
    "type": "complete",
    "step_id": "fi.mau.meta.complete",
    "complete": {"user_login_id": "L1"},
}


def test_traducao_de_formatos_reais():
    v = translate_step(IG_CRED)
    assert v.step.kind == "credentials" and v.state == State.PENDING_AUTH
    assert v.step.instructions.startswith("Enter your Instagram")
    v = translate_step(CAPTCHA)
    assert v.step.kind == "captcha" and v.state == State.AWAITING_CHALLENGE
    assert {a.kind for a in v.step.attachments} == {"image", "audio"}
    assert v.step.fields[0].type == "captcha_code"
    v = translate_step(MFA_CHOICE)
    assert v.step.kind == "choice" and v.step.fields[0].options == ["SMS", "WhatsApp"]
    v = translate_step(OTP)
    assert v.step.kind == "code_2fa" and v.state == State.AWAITING_2FA
    assert v.step.fields[0].secret


class Script:
    """Bridge que responde uma lista fixa, na ordem; guarda o que recebeu."""

    def __init__(self, *responses):
        self.responses = list(responses)
        self.received: list[tuple[str, dict]] = []

    def transport(self):
        def handle(req: httpx.Request):
            body = json.loads(req.content) if req.content else {}
            self.received.append((req.url.path, body))
            return httpx.Response(200, json=self.responses.pop(0))

        return httpx.MockTransport(handle)


def adapter(script: Script):
    return MatrixBridgeAdapter(
        "instagram", ProvisioningClient("http://b", "s" * 20, transport=script.transport())
    )


CTX = ConnectionCtx(id="c1", account_id=1, provider="instagram", matrix_user="@luar_t1_c1:x")


async def test_conta_inexistente_vem_como_dialogo_e_vira_erro_no_mesmo_passo():
    sc = Script(IG_CRED, DIALOG, IG_CRED)
    a = adapter(sc)
    await a.start_login(CTX, "android")
    v = await a.submit_step(CTX, "s", "credentials", {"username": "x", "password": "y"})
    assert v.step.kind == "credentials" and v.step.error_code == "account_not_found"
    # o adaptador respondeu "Try again" sozinho ao dialogo
    assert sc.received[-1][1] == {"dialog_action": "Try again"}


async def test_codigo_errado_repete_o_passo_e_vira_wrong_code():
    sc = Script(OTP, OTP_AGAIN, COMPLETE)
    a = adapter(sc)
    await a.start_login(CTX, "android")
    v = await a.submit_step(CTX, "s", "code_2fa", {"otp_code": "000000"})
    assert v.step.kind == "code_2fa" and v.step.error_code == "wrong_code"
    v = await a.submit_step(CTX, "s", "code_2fa", {"otp_code": "123456"})
    assert v.state == State.CONNECTED and v.login_id == "L1"


async def test_escolha_de_metodo_e_captcha_seguem_sem_erro():
    sc = Script(IG_CRED, MFA_CHOICE, CAPTCHA, COMPLETE)
    a = adapter(sc)
    await a.start_login(CTX, "android")
    v = await a.submit_step(CTX, "s", "credentials", {"username": "u", "password": "p"})
    assert v.step.kind == "choice" and v.step.error_code is None
    v = await a.submit_step(CTX, "s", "choice", {"mfatype": "SMS"})
    assert v.step.kind == "captcha" and v.step.error_code is None
    v = await a.submit_step(CTX, "s", "captcha", {"captcha_code": "abcd"})
    assert v.state == State.CONNECTED


@pytest.mark.parametrize("pw", ["senha-super-secreta-123"])
async def test_senha_nao_aparece_na_visao_devolvida(pw):
    sc = Script(IG_CRED, DIALOG, IG_CRED)
    a = adapter(sc)
    await a.start_login(CTX, "android")
    v = await a.submit_step(CTX, "s", "credentials", {"username": "u", "password": pw})
    assert pw not in v.model_dump_json()
