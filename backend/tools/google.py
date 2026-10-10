"""The Google tools the agent can call (contracts § Tools): Calendar, Gmail, Tasks, Drive and
Docs on the Workspace account, and flight search. All of them only read.

The Workspace functions are declared only with WORKSPACE_MODE=rest and the Google OAuth
variables set; `flights_search` always is, because without SerpApi it still gives a Google
Flights link. `run` never raises: a missing credential or a failing API comes back as
{"error": ...} for the model to explain.
"""

from __future__ import annotations

import logging
import os
import time
from typing import Any, Awaitable, Callable

import httpx

from tools import google_auth
from tools.drive import drive_read, drive_search
from tools.flights import flights_search
from tools.gcalendar import calendar_events, calendar_free_slots
from tools.gmail import gmail_read, gmail_search
from tools.tasks import tasks_list

log = logging.getLogger(__name__)

_STR = {"type": "string"}
_TIME = {"type": "string", "description": "ISO 8601, e.g. 2026-10-15T08:00:00+02:00"}
_DATE = {"type": "string", "description": "YYYY-MM-DD"}


def _fn(name: str, description: str, required: dict, optional: dict | None = None) -> dict:
    return {
        "type": "function",
        "name": name,
        "description": description,
        "parameters": {"type": "object", "properties": {**required, **(optional or {})}, "required": [*required]},
    }


WORKSPACE_DECLARATIONS = [
    _fn(
        "calendar_events",
        "The user's calendar events in a time window, at most 20, optionally matching words in the title. "
        "Use it for days beyond the preloaded week or to search the calendar.",
        {"time_min": _TIME, "time_max": _TIME},
        {"query": {"type": "string", "description": "words to match, e.g. dentist"}},
    ),
    _fn(
        "calendar_free_slots",
        "Free time slots in a window, between 08:00 and 20:00 Zurich time, at most 8. With attendees, only "
        "slots where all of them are free too.",
        {"time_min": _TIME, "time_max": _TIME},
        {
            "duration_min": {"type": "integer", "description": "minimum slot length in minutes, default 30"},
            "attendees": {"type": "array", "items": _STR, "description": "other people's calendar email addresses"},
        },
    ),
    _fn(
        "gmail_search",
        "Search the user's Gmail with Gmail search syntax, newest first, at most 5 with subject, sender, date "
        "and snippet.",
        {"query": {"type": "string", "description": "e.g. 'from:swiss.com booking' or 'subject:invoice newer_than:30d'"}},
    ),
    _fn(
        "gmail_read",
        "Read one email's text, e.g. a booking confirmation found with gmail_search.",
        {"message_id": {"type": "string", "description": "id from gmail_search"}},
    ),
    _fn("tasks_list", "The user's open Google Tasks across all lists, due ones first, at most 20.", {}),
    _fn(
        "drive_search",
        "Find Google Drive files (Docs, Sheets, Slides, PDFs) by words in the name or text, at most 5.",
        {"query": {"type": "string", "description": "e.g. packing list"}},
    ),
    _fn(
        "drive_read",
        "Read the text of a Google Doc, Sheet or Slides deck found with drive_search, at most 4000 characters.",
        {"file_id": {"type": "string", "description": "id from drive_search"}},
    ),
]

FLIGHTS_DECLARATION = _fn(
    "flights_search",
    "Search new flights on Google Flights, at most 4, plus a Google Flights link for the search. Not for "
    "flights the user already booked: those are in the emails.",
    {
        "origin": {"type": "string", "description": "IATA airport code, e.g. ZRH"},
        "destination": {"type": "string", "description": "IATA airport code, e.g. LIS"},
        "departure_date": _DATE,
    },
    {"return_date": _DATE},
)

SCOPE = "https://www.googleapis.com/auth/"
# The scope each Workspace tool needs; a token without it gets HTTP 403, a wasted model step.
NEEDS = {
    "calendar_events": "calendar.readonly",
    "calendar_free_slots": "calendar.readonly",
    "gmail_search": "gmail.readonly",
    "gmail_read": "gmail.readonly",
    "tasks_list": "tasks.readonly",
    "drive_search": "drive.readonly",
    "drive_read": "drive.readonly",
}

GOOGLE_TOOLS: dict[str, tuple[Callable[..., Awaitable[dict]], str]] = {
    "calendar_events": (calendar_events, "Checking your calendar…"),
    "calendar_free_slots": (calendar_free_slots, "Finding a free slot…"),
    "gmail_search": (gmail_search, "Searching your mail…"),
    "gmail_read": (gmail_read, "Reading the email…"),
    "tasks_list": (tasks_list, "Checking your tasks…"),
    "drive_search": (drive_search, "Searching your Drive…"),
    "drive_read": (drive_read, "Reading the document…"),
    "flights_search": (flights_search, "Searching flights…"),
}


def workspace_enabled() -> bool:
    return os.environ.get("WORKSPACE_MODE", "fixture").lower() == "rest" and google_auth.oauth_configured()


def _granted(name: str, scopes: set[str]) -> bool:
    need = NEEDS[name]
    broader = need.removesuffix(".readonly")  # e.g. calendar covers calendar.readonly
    return bool({SCOPE + need, SCOPE + broader} & scopes) or (name.startswith("gmail") and "https://mail.google.com/" in scopes)


def google_declarations(scopes: set[str] | None = None) -> list[dict]:
    """With `scopes` known, only the Workspace tools the token may call."""
    if not workspace_enabled():
        return [FLIGHTS_DECLARATION]
    tools = [d for d in WORKSPACE_DECLARATIONS if scopes is None or _granted(d["name"], scopes)]
    return [*tools, FLIGHTS_DECLARATION]


async def granted_scopes() -> set[str] | None:
    """The Workspace token's scopes, or None without Workspace or when Google can't say."""
    return await google_auth.granted_scopes() if workspace_enabled() else None


async def run(name: str, args: dict[str, Any]) -> dict[str, Any]:
    """Call one Google tool with the model's arguments; errors come back as {"error": ...}."""
    fn, _ = GOOGLE_TOOLS[name]
    t0 = time.monotonic()
    try:
        result = await fn(**args)
    except google_auth.NotConfigured as e:
        log.warning("%s not configured: %s", name, e)
        return {"error": f"not configured: {e}"}
    except httpx.HTTPStatusError as e:
        log.warning("%s %s failed: HTTP %s %s", name, args, e.response.status_code, e.response.text[:300])
        return {"error": f"Google answered HTTP {e.response.status_code}"}
    except (TypeError, ValueError) as e:  # bad arguments from the model
        log.warning("%s %s rejected: %s", name, args, e)
        return {"error": f"invalid arguments: {e}"}
    except Exception as e:
        log.warning("%s %s failed: %r", name, args, e)
        return {"error": f"lookup failed: {type(e).__name__}"}
    log.info("%s %s took %.2f s", name, args, time.monotonic() - t0)
    return result
