"""Workspace context loader (Calendar & Gmail REST APIs or fixture) (contracts § Tools)."""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import logging
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import httpx

log = logging.getLogger(__name__)

TZ = ZoneInfo("Europe/Zurich")
FIXTURES_PATH = Path(__file__).parent / "fixtures" / "context.json"
DEV_FIXTURES_PATH = Path(__file__).parent / "fixtures" / "dev_context.json"

OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token"
CALENDAR_EVENTS_URL = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
GMAIL_MESSAGES_URL = "https://www.googleapis.com/gmail/v1/users/me/messages"


def _extract_body(payload: dict[str, Any]) -> str:
    """Extract plain text body from Gmail payload parts, base64url decoded."""
    body_data = payload.get("body", {}).get("data")
    if body_data:
        try:
            return base64.urlsafe_b64decode(body_data.encode()).decode("utf-8", errors="replace")
        except Exception:
            pass

    for part in payload.get("parts", []):
        if part.get("mimeType") == "text/plain" and part.get("body", {}).get("data"):
            try:
                return base64.urlsafe_b64decode(part["body"]["data"].encode()).decode("utf-8", errors="replace")
            except Exception:
                pass
        sub = _extract_body(part)
        if sub:
            return sub
    return ""


async def _refresh_access_token(client_id: str, client_secret: str, refresh_token: str) -> str:
    async with httpx.AsyncClient(timeout=10) as http:
        resp = await http.post(
            OAUTH_TOKEN_URL,
            data={
                "client_id": client_id,
                "client_secret": client_secret,
                "refresh_token": refresh_token,
                "grant_type": "refresh_token",
            },
        )
        resp.raise_for_status()
        return resp.json()["access_token"]


async def _load_context_rest() -> dict[str, Any]:
    client_id = os.environ.get("GOOGLE_CLIENT_ID", "")
    client_secret = os.environ.get("GOOGLE_CLIENT_SECRET", "")
    refresh_token = os.environ.get("GOOGLE_REFRESH_TOKEN", "")

    if not (client_id and client_secret and refresh_token):
        log.warning("Google OAuth credentials missing, falling back to fixture")
        return _load_context_fixture()

    access_token = await _refresh_access_token(client_id, client_secret, refresh_token)
    headers = {"Authorization": f"Bearer {access_token}"}

    now = datetime.now(TZ)
    time_min = now.isoformat()
    time_max = (now + timedelta(days=7)).isoformat()

    events_list: list[dict[str, Any]] = []
    flight_emails: list[dict[str, Any]] = []

    async with httpx.AsyncClient(timeout=10) as http:
        # 1. Calendar events
        try:
            cal_resp = await http.get(
                CALENDAR_EVENTS_URL,
                headers=headers,
                params={
                    "timeMin": time_min,
                    "timeMax": time_max,
                    "singleEvents": "true",
                    "orderBy": "startTime",
                },
            )
            cal_resp.raise_for_status()
            for item in cal_resp.json().get("items", []):
                start = item.get("start", {}).get("dateTime") or item.get("start", {}).get("date")
                end = item.get("end", {}).get("dateTime") or item.get("end", {}).get("date")
                description = (item.get("description") or "").lower()
                organizer = (item.get("organizer", {}).get("email") or "").lower()
                source = "luma" if ("lu.ma" in description or "lu.ma" in organizer or "luma" in description) else "calendar"

                ev: dict[str, Any] = {
                    "title": item.get("summary", "Untitled"),
                    "start": start,
                    "end": end,
                    "source": source,
                }
                if item.get("location"):
                    ev["location"] = item["location"]
                events_list.append(ev)
        except Exception as exc:
            log.warning("Calendar events fetch failed: %s", exc)

        # 2. Gmail flight emails
        try:
            gmail_list = await http.get(
                GMAIL_MESSAGES_URL,
                headers=headers,
                params={"q": "flight OR booking", "maxResults": 5},
            )
            gmail_list.raise_for_status()
            msg_ids = [m["id"] for m in gmail_list.json().get("messages", [])]

            for msg_id in msg_ids:
                msg_resp = await http.get(
                    f"{GMAIL_MESSAGES_URL}/{msg_id}",
                    headers=headers,
                    params={"format": "full"},
                )
                msg_resp.raise_for_status()
                data = msg_resp.json()
                headers_list = data.get("payload", {}).get("headers", [])
                h_map = {h.get("name", "").lower(): h.get("value", "") for h in headers_list}

                subject = h_map.get("subject", "")
                from_hdr = h_map.get("from", "")
                date_hdr = h_map.get("date", "")
                body_text = _extract_body(data.get("payload", {}))[:2000]

                flight_emails.append({
                    "subject": subject,
                    "from": from_hdr,
                    "date": date_hdr,
                    "body": body_text,
                })
        except Exception as exc:
            log.warning("Gmail messages fetch failed: %s", exc)

    return {"events": events_list, "flight_emails": flight_emails}


def _load_context_fixture() -> dict[str, Any]:
    path = FIXTURES_PATH if FIXTURES_PATH.exists() else DEV_FIXTURES_PATH
    return json.loads(path.read_text())


async def load_context() -> dict[str, Any]:
    """Load context once per session (contracts § Tools).
    WORKSPACE_MODE=fixture returns fixtures/context.json.
    WORKSPACE_MODE=rest calls Calendar and Gmail REST APIs with refresh token.
    """
    mode = os.environ.get("WORKSPACE_MODE", "fixture").lower()
    if mode == "rest":
        try:
            return await _load_context_rest()
        except Exception as exc:
            log.warning("REST context load failed, falling back to fixture: %s", exc)
            return _load_context_fixture()
    return _load_context_fixture()


def load_context_sync() -> dict[str, Any]:
    """Synchronous version of load_context()."""
    return asyncio.run(load_context())


if __name__ == "__main__":
    from dotenv import load_dotenv

    load_dotenv()
    load_dotenv("../.env")

    parser = argparse.ArgumentParser(description="Load workspace context")
    parser.add_argument("--mode", default=os.environ.get("WORKSPACE_MODE", "fixture"))
    args = parser.parse_args()

    os.environ["WORKSPACE_MODE"] = args.mode
    data = load_context_sync()
    print(json.dumps(data, indent=2, ensure_ascii=False))
