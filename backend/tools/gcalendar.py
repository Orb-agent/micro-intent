"""Google Calendar tools: events in a window, and free slots across one or more calendars
(contracts § Tools). Read-only, scope calendar.readonly.

Named gcalendar so it never shadows the standard library's calendar module.
Live smoke test, from backend/:
    uv run python -m tools.gcalendar events 2026-10-15
    uv run python -m tools.gcalendar free 2026-10-15 --minutes 60 --with someone@example.com
"""

from __future__ import annotations

import argparse
import asyncio
from datetime import date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo

import httpx

from tools import google_auth

TZ = ZoneInfo("Europe/Zurich")
EVENTS_URL = "https://www.googleapis.com/calendar/v3/calendars/{calendar}/events"
FREEBUSY_URL = "https://www.googleapis.com/calendar/v3/freeBusy"
MAX_EVENTS = 20
MAX_SLOTS = 8
DAY = (time(8), time(20))  # free slots only inside these local hours


def parse_time(value: str) -> datetime:
    """ISO 8601 date or date-time; without an offset it is Europe/Zurich time."""
    when = datetime.fromisoformat(value)
    return when.astimezone(TZ) if when.tzinfo else when.replace(tzinfo=TZ)


def _iso(value: datetime) -> str:
    return value.astimezone(TZ).isoformat()


def event_from_item(item: dict[str, Any]) -> dict[str, Any]:
    """Calendar API event → the event shape of contracts § Tools (Context) and § Cards."""
    start, end = item.get("start", {}), item.get("end", {})
    description = (item.get("description") or "").lower()
    organizer = (item.get("organizer", {}).get("email") or "").lower()
    event: dict[str, Any] = {
        "title": item.get("summary", "Untitled"),
        "source": "luma" if "lu.ma" in organizer or "lu.ma" in description or "luma" in description else "calendar",
    }
    if "dateTime" in start:
        event["start"], event["end"] = _iso(parse_time(start["dateTime"])), _iso(parse_time(end["dateTime"]))
    else:  # all-day: midnight to midnight local, so the times fit an event card
        event["start"], event["end"] = _iso(parse_time(start["date"])), _iso(parse_time(end["date"]))
        event["all_day"] = True
    if item.get("location"):
        event["location"] = item["location"]
    return event


async def calendar_events(
    time_min: str,
    time_max: str,
    query: str | None = None,
    client: httpx.AsyncClient | None = None,
) -> dict[str, Any]:
    """The user's events overlapping [time_min, time_max), at most 20, optionally matching a text query."""
    params: dict[str, Any] = {
        "timeMin": _iso(parse_time(time_min)),
        "timeMax": _iso(parse_time(time_max)),
        "singleEvents": "true",
        "orderBy": "startTime",
        "maxResults": MAX_EVENTS,
    }
    if query:
        params["q"] = query
    data = await google_auth.get(EVENTS_URL.format(calendar="primary"), client, **params)
    return {"events": [event_from_item(item) for item in data.get("items", []) if item.get("status") != "cancelled"]}


def _merge(busy: list[tuple[datetime, datetime]]) -> list[tuple[datetime, datetime]]:
    merged: list[tuple[datetime, datetime]] = []
    for start, end in sorted(busy):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def free_slots(
    busy: list[tuple[datetime, datetime]], start: datetime, end: datetime, minutes: int
) -> list[dict[str, str]]:
    """Gaps of at least `minutes` between busy intervals, inside local day hours (DAY)."""
    slots: list[dict[str, str]] = []
    merged = _merge(busy)
    day: date = start.astimezone(TZ).date()
    while day <= end.astimezone(TZ).date() and len(slots) < MAX_SLOTS:
        cursor = max(start, datetime.combine(day, DAY[0], TZ))
        day_end = min(end, datetime.combine(day, DAY[1], TZ))
        for b_start, b_end in [*merged, (day_end, day_end)]:
            if b_end <= cursor:
                continue
            gap_end = min(b_start, day_end)
            if gap_end - cursor >= timedelta(minutes=minutes):
                slots.append({"start": _iso(cursor), "end": _iso(gap_end)})
            cursor = max(cursor, b_end)
            if cursor >= day_end:
                break
        day += timedelta(days=1)
    return slots[:MAX_SLOTS]


async def calendar_free_slots(
    time_min: str,
    time_max: str,
    duration_min: int = 30,
    attendees: list[str] | None = None,
    client: httpx.AsyncClient | None = None,
) -> dict[str, Any]:
    """Free slots of at least duration_min that the user and every attendee share, between
    08:00 and 20:00 Zurich time, at most 8. Attendees are calendar ids (email addresses) the
    account can see free/busy for; ones it can't see are listed under `unavailable`."""
    start, end = parse_time(time_min), parse_time(time_max)
    if end <= start:
        raise ValueError("time_max must be after time_min")
    calendars = ["primary", *(attendees or [])]
    body = {"timeMin": _iso(start), "timeMax": _iso(end), "timeZone": "Europe/Zurich", "items": [{"id": c} for c in calendars]}
    data = (await google_auth.request("POST", FREEBUSY_URL, client, json=body)).json()
    busy: list[tuple[datetime, datetime]] = []
    unavailable: list[str] = []
    for calendar_id, info in data.get("calendars", {}).items():
        if info.get("errors"):
            unavailable.append(calendar_id)
            continue
        busy += [(parse_time(b["start"]), parse_time(b["end"])) for b in info.get("busy", [])]
    result: dict[str, Any] = {"slots": free_slots(busy, start, end, int(duration_min))}
    if unavailable:
        result["unavailable"] = unavailable
    return result


def _day_window(day: str) -> tuple[str, str]:
    start = parse_time(day)
    return start.isoformat(), (start + timedelta(days=1)).isoformat()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Live smoke test for the Calendar tools")
    sub = parser.add_subparsers(dest="command", required=True)
    events = sub.add_parser("events", help="events on one day")
    events.add_argument("day", nargs="?", default=date.today().isoformat())
    free = sub.add_parser("free", help="free slots on one day")
    free.add_argument("day", nargs="?", default=date.today().isoformat())
    free.add_argument("--minutes", type=int, default=30)
    free.add_argument("--with", dest="attendees", action="append", default=[])
    args = parser.parse_args()
    window = _day_window(args.day)
    if args.command == "events":
        google_auth.smoke(lambda: calendar_events(*window))
    else:
        google_auth.smoke(lambda: calendar_free_slots(*window, args.minutes, args.attendees))
