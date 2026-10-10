"""Ephemeral Gemini Live tokens, so the extension never holds the API key."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from google import genai
from google.genai import types

from .config import settings

API_VERSION = "v1alpha"


def mint_live_token() -> dict:
    now = datetime.now(timezone.utc)
    expires = now + timedelta(minutes=30)
    new_session_expires = now + timedelta(minutes=1)
    client = genai.Client(api_key=settings.gemini_api_key, http_options={"api_version": API_VERSION})
    token = client.auth_tokens.create(
        config=types.CreateAuthTokenConfig(
            uses=1,
            expire_time=expires,
            new_session_expire_time=new_session_expires,
            # Lock only the model; the client chooses its own session config.
            live_connect_constraints=types.LiveConnectConstraints(model=settings.live_model),
            lock_additional_fields=[],
        )
    )
    return {
        "token": token.name,
        "model": settings.live_model,
        "api_version": API_VERSION,
        "expires_at": expires.isoformat().replace("+00:00", "Z"),
        "new_session_expires_at": new_session_expires.isoformat().replace("+00:00", "Z"),
    }
