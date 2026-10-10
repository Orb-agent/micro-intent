"""Runtime configuration from environment variables (see ../.env.example)."""

from __future__ import annotations

import os
from dataclasses import dataclass
from zoneinfo import ZoneInfo


def _bool(name: str, default: bool = False) -> bool:
    return os.getenv(name, str(default)).strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    gemini_api_key: str | None
    model: str
    live_model: str
    calendar_source: str
    google_calendar_token_file: str | None
    google_calendar_id: str
    force_fallback: bool
    tz: ZoneInfo
    agent_timeout_s: float
    sbb_timeout_s: float
    profile_path: str | None


def load_settings() -> Settings:
    return Settings(
        gemini_api_key=os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY") or None,
        model=os.getenv("MICRO_INTENT_MODEL", "gemini-3.8-flash"),
        live_model=os.getenv("MICRO_INTENT_LIVE_MODEL", "gemini-3.8-live"),
        calendar_source=os.getenv("CALENDAR_SOURCE", "mock").strip().lower(),
        google_calendar_token_file=os.getenv("GOOGLE_CALENDAR_TOKEN_FILE") or None,
        google_calendar_id=os.getenv("GOOGLE_CALENDAR_ID", "primary"),
        force_fallback=_bool("MICRO_INTENT_FORCE_FALLBACK"),
        tz=ZoneInfo(os.getenv("MICRO_INTENT_TZ", "Europe/Zurich")),
        agent_timeout_s=float(os.getenv("MICRO_INTENT_AGENT_TIMEOUT_S", "40")),
        sbb_timeout_s=float(os.getenv("MICRO_INTENT_SBB_TIMEOUT_S", "6")),
        profile_path=os.getenv("MICRO_INTENT_PROFILE_PATH") or None,
    )


settings = load_settings()
