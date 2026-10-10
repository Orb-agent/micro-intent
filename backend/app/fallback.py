"""Scripted planner used when Gemini (or the network) is unavailable.

It reads the event from the page text with plain parsing, uses the same tools as the agent
(calendar, SBB with its own scripted timetable fallback) and builds the same kind of turn.
"""

from __future__ import annotations

import re
from datetime import date, datetime, time, timedelta
from typing import Any

from .compose import build_turn, split_calendar
from .fmt import hm
from .models import IntentRequest
from .tools import RequestCtx, propose_draft_message, propose_set_reminder, sbb_connections

_MONTHS = {
    "jan": 1, "januar": 1, "january": 1, "feb": 2, "februar": 2, "february": 2, "mar": 3, "mär": 3, "märz": 3, "march": 3,
    "apr": 4, "april": 4, "may": 5, "mai": 5, "jun": 6, "juni": 6, "june": 6, "jul": 7, "juli": 7, "july": 7,
    "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10, "okt": 10, "oktober": 10, "october": 10,
    "nov": 11, "november": 11, "dec": 12, "dez": 12, "dezember": 12, "december": 12,
}
_MONTH_RE = "|".join(sorted(_MONTHS, key=len, reverse=True))
_TIME = r"(\d{1,2})(?::(\d{2}))?\s*(am|pm|AM|PM|a\.m\.|p\.m\.)?"
_CITIES = ["Zürich", "Zurich", "Winterthur", "Bern", "Basel", "Lausanne", "Genève", "Geneva", "Luzern", "Lucerne", "St. Gallen", "Lugano", "Zug"]
_DEFAULT_START, _DEFAULT_END = time(18, 0), time(21, 0)


def _text_sources(req: IntentRequest) -> str:
    c = req.context
    parts = [
        c.selection.text if c.selection else None,
        c.selection.element.text if c.selection and c.selection.element else None,
        c.gaze.text if c.gaze else None,
        c.title,
        (c.page_text or "")[:5000],
    ]
    return "\n".join(p for p in parts if p)


def _parse_date(text: str, today: date) -> date:
    low = text.lower()
    if m := re.search(r"\b(20\d\d)-(\d{2})-(\d{2})\b", text):
        return date(int(m[1]), int(m[2]), int(m[3]))
    if m := re.search(r"\b(\d{1,2})\.(\d{1,2})\.(20\d\d)\b", text):
        return date(int(m[3]), int(m[2]), int(m[1]))
    if m := re.search(rf"\b({_MONTH_RE})\.?\s+(\d{{1,2}})(?:st|nd|rd|th)?\b", low):
        return _with_year(today, _MONTHS[m[1]], int(m[2]))
    if m := re.search(rf"\b(\d{{1,2}})\.?\s+({_MONTH_RE})\b", low):
        return _with_year(today, _MONTHS[m[2]], int(m[1]))
    if re.search(r"\b(tomorrow|morgen)\b", low):
        return today + timedelta(days=1)
    return today


def _with_year(today: date, month: int, day: int) -> date:
    try:
        d = date(today.year, month, day)
    except ValueError:
        return today
    return d if d >= today - timedelta(days=1) else date(today.year + 1, month, day)


def _to_time(h: str, m: str | None, ampm: str | None) -> time | None:
    hour, minute = int(h), int(m or 0)
    if ampm:
        ap = ampm.lower().replace(".", "")
        if ap == "pm" and hour < 12:
            hour += 12
        if ap == "am" and hour == 12:
            hour = 0
    if not (0 <= hour < 24 and 0 <= minute < 60):
        return None
    return time(hour, minute)


def _parse_times(text: str) -> tuple[time, time]:
    rng = re.search(rf"{_TIME}\s*(?:-|–|—|to|bis)\s*{_TIME}", text)
    if rng and (rng[2] or rng[3]) and (rng[5] or rng[6]):
        start = _to_time(rng[1], rng[2], rng[3] or rng[6])
        end = _to_time(rng[4], rng[5], rng[6])
        if start and end:
            return start, end
    single = re.search(r"\b(\d{1,2}):(\d{2})\s*(am|pm|AM|PM)?", text) or re.search(r"\b(\d{1,2})()\s*(am|pm|AM|PM)\b", text)
    if single and (start := _to_time(single[1], single[2] or None, single[3])):
        return start, (datetime.combine(date.today(), start) + timedelta(hours=3)).time()
    return _DEFAULT_START, _DEFAULT_END


def _parse_location(text: str) -> str | None:
    for city in _CITIES:
        if re.search(rf"\b{re.escape(city)}\b", text, re.IGNORECASE):
            return "Zürich" if city.lower() in {"zurich", "zürich"} else city
    return None


def _clean_title(title: str) -> str:
    title = re.split(r"\s+[|·–-]\s+Luma\b", title)[0]
    return title.strip() or "Event"


def parse_event(req: IntentRequest, now: datetime) -> dict[str, Any]:
    text = _text_sources(req)
    day = _parse_date(text, now.date())
    t0, t1 = _parse_times(text)
    start = datetime.combine(day, t0, now.tzinfo)
    end = datetime.combine(day, t1, now.tzinfo)
    if end <= start:
        end += timedelta(days=1)
    loc = _parse_location(text)
    ev = {"title": _clean_title(req.context.title), "start": start.isoformat(), "end": end.isoformat()}
    if loc:
        ev["location"] = loc
    return ev


def _origin(intent: str, home: str) -> str:
    m = re.search(r"\b(?:from|von|ab)\s+([A-ZÄÖÜ][\w.\-äöüÄÖÜ]*(?:\s+(?:HB|[A-ZÄÖÜ][\w.\-äöüÄÖÜ]*))*)", intent)
    return m[1] if m else home


def _station(location: str | None) -> str:
    if not location or location.lower() in {"zürich", "zurich"}:
        return "Zürich HB"
    return location


def _has(pattern: str, text: str) -> bool:
    return re.search(pattern, text, re.IGNORECASE) is not None


def plan(req: IntentRequest, ctx: RequestCtx) -> dict[str, Any]:
    intent = req.intent
    de = ctx.locale == "de"
    wants_travel = _has(r"get there|how do i get|train|travel|commute|route|hinkommen|anreise|zug|fahr|\bfrom\b|\bvon\b", intent)
    wants_free = _has(r"\bfree\b|available|busy|conflict|calendar|frei|zeit|kalender|termin", intent)
    wants_reminder = _has(r"remind|erinner", intent)
    contact = next(
        (c for c in ctx.profile.contacts if _has(rf"\b({re.escape(c.name)}|{re.escape(c.id)}|{re.escape(c.relation or c.id)})\b", intent)),
        None,
    )
    if contact is None and _has(r"\b(mum|mama|mother|mutter)\b", intent):
        contact = next((c for c in ctx.profile.contacts if c.relation == "mother"), None)
    wants_message = contact is not None and _has(r"tell|notify|message|text|let .* know|sag|schreib|benachrichtig|inform", intent)

    ev = parse_event(req, ctx.now)
    ctx.event = ev
    start, end = datetime.fromisoformat(ev["start"]), datetime.fromisoformat(ev["end"])
    conflicts, _ = split_calendar(ev, (start, end))
    ctx.busy_checked.append((start, end))

    train = None
    if wants_travel or not (wants_free or wants_reminder or wants_message):
        origin = _origin(intent, ctx.profile.home)
        target = start
        if target > ctx.now:
            res = sbb_connections(ctx, origin, _station(ev.get("location")), target.isoformat(), True, 4)
        else:
            res = sbb_connections(ctx, origin, _station(ev.get("location")), ctx.now.isoformat(), False, 4)
        items = res.get("items") or []
        train = next((c for c in items if c.get("recommended")), items[0] if items else None)

    if wants_reminder:
        at = datetime.fromisoformat(train["departure"]) - timedelta(minutes=15) if train else start - timedelta(hours=1)
        at = max(at, ctx.now + timedelta(minutes=5))
        text = (f"Los zu {ev['title']}" if de else f"Leave for {ev['title']}") if train else ev["title"]
        propose_set_reminder(ctx, text, at.isoformat())
    if wants_message and contact:
        body = (
            f"Hi {contact.name}, ich bin heute Abend bei {ev['title']} ({hm(start)}-{hm(end)}). Ich melde mich, wenn ich losfahre."
            if de
            else f"Hi {contact.name}, I'm at {ev['title']} tonight ({hm(start)}-{hm(end)}). I'll text you when I head home."
        )
        propose_draft_message(ctx, contact.id, body)

    say = _say(ctx, conflicts, train)
    return build_turn(ctx, say, [{"component": "EventCard", "event": ev}], "fallback")


def _say(ctx: RequestCtx, conflicts: list, train: dict[str, Any] | None) -> str:
    de = ctx.locale == "de"
    parts = []
    if conflicts:
        c = conflicts[0]
        parts.append(f"Achtung: {c.title} um {hm(c.start)} überschneidet sich." if de else f"Heads up: {c.title} overlaps at {hm(c.start)}.")
    else:
        parts.append("Du hast dann Zeit." if de else "You're free then.")
    if train:
        product = (train.get("products") or ["train"])[0]
        conn = ctx.connections or {}
        parts.append(
            f"Der {product} um {hm(train['departure'])} ab {conn.get('from')} ist um {hm(train['arrival'])} in {conn.get('to')}."
            if de
            else f"The {hm(train['departure'])} {product} from {conn.get('from')} gets you to {conn.get('to')} by {hm(train['arrival'])}."
        )
    return " ".join(parts)
