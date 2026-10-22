"""Estados da conexão de canal e transições permitidas (Fase CH)."""

from enum import StrEnum


class State(StrEnum):
    PENDING_AUTH = "pending_auth"
    AWAITING_2FA = "awaiting_2fa"
    AWAITING_CHALLENGE = "awaiting_challenge"
    CONNECTED = "connected"
    DEGRADED = "degraded"
    REAUTH_REQUIRED = "reauth_required"
    DISCONNECTED = "disconnected"
    REVOKED = "revoked"


LOGIN_STATES = {State.PENDING_AUTH, State.AWAITING_2FA, State.AWAITING_CHALLENGE}

_ALLOWED: dict[State, set[State]] = {
    State.PENDING_AUTH: {
        State.AWAITING_2FA,
        State.AWAITING_CHALLENGE,
        State.CONNECTED,
        State.DISCONNECTED,
        State.REVOKED,
    },
    State.AWAITING_2FA: {
        State.PENDING_AUTH,
        State.AWAITING_CHALLENGE,
        State.CONNECTED,
        State.DISCONNECTED,
        State.REVOKED,
    },
    State.AWAITING_CHALLENGE: {
        State.PENDING_AUTH,
        State.AWAITING_2FA,
        State.CONNECTED,
        State.DISCONNECTED,
        State.REVOKED,
    },
    State.CONNECTED: {State.DEGRADED, State.REAUTH_REQUIRED, State.DISCONNECTED, State.REVOKED},
    State.DEGRADED: {State.CONNECTED, State.REAUTH_REQUIRED, State.DISCONNECTED, State.REVOKED},
    State.REAUTH_REQUIRED: {
        State.PENDING_AUTH,
        State.AWAITING_2FA,
        State.AWAITING_CHALLENGE,
        State.CONNECTED,
        State.DISCONNECTED,
        State.REVOKED,
    },
    State.DISCONNECTED: {State.PENDING_AUTH, State.REVOKED},
    State.REVOKED: set(),
}


class InvalidTransition(ValueError):
    pass


def can_transition(old: State, new: State) -> bool:
    return old == new or new in _ALLOWED[old]


def check_transition(old: State, new: State) -> None:
    if not can_transition(old, new):
        raise InvalidTransition(f"{old} -> {new}")
