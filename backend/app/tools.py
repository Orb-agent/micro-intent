"""Agent tools.

Read tools run immediately.
Write tools never run during /intent: they register a PendingAction with a server-written preview and only execute via /confirm.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, time, timedelta
from typing import Any
from urllib.parse import quote

from . import sbb
from .calendar_source import ME, busy_and_conflicts, free_slots, get_calendar
from .fmt import day_label, hm, parse_dt
from .models import Profile
from .state import PendingAction, store

log = logging.getLogger(__name__)

WRITE_TOOLS = {"calendar_create", "calendar_move", "set_reminder", "draft_message"}

_ISO = "ISO 8601 date-time with offset, e.g. 2026-10-10T18:00:00+02:00"

TOOL_DECLARATIONS: list[dict[str, Any]] = [
    {
        "type": "function",
        "name": "calendar_free_busy",
        "description": "Read the user's calendar between start and end. Returns busy events (id, title, start, end) that overlap the window.",
        "parameters": {
            "type": "object",
            "properties": {"start": {"type": "string", "description": _ISO}, "end": {"type": "string", "description": _ISO}},
            "required": ["start", "end"],
        },
    },
    {
        "type": "function",
        "name": "sbb_connections",
        "description": "Swiss public transport connections (SBB timetable). Use station or town names. With is_arrival_time=true, `datetime` is the latest arrival.",
        "parameters": {
            "type": "object",
            "properties": {
                "origin": {"type": "string", "description": "Departure station or town, e.g. Winterthur"},
                "destination": {"type": "string", "description": "Arrival station or town, e.g. Zürich HB"},
                "datetime": {"type": "string", "description": _ISO},
                "is_arrival_time": {"type": "boolean"},
                "limit": {"type": "integer", "description": "1-6, default 4"},
            },
            "required": ["origin", "destination", "datetime"],
        },
    },
    {
        "type": "function",
        "name": "shared_free_slot",
        "description": "Find free slots shared by the user and contacts (by contact id from the profile) on one day.",
        "parameters": {
            "type": "object",
            "properties": {
                "participants": {"type": "array", "items": {"type": "string"}, "description": "Contact ids; the user is always included"},
                "date": {"type": "string", "description": "YYYY-MM-DD"},
                "duration_min": {"type": "integer"},
                "earliest": {"type": "string", "description": "HH:MM, default 08:00"},
                "latest": {"type": "string", "description": "HH:MM, default 22:00"},
            },
            "required": ["participants", "date", "duration_min"],
        },
    },
    {
        "type": "function",
        "name": "calendar_create",
        "description": "PROPOSE creating a calendar event. Does not write; returns an action_id the human must approve.",
        "parameters": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "start": {"type": "string", "description": _ISO},
                "end": {"type": "string", "description": _ISO},
                "location": {"type": "string"},
                "description": {"type": "string"},
            },
            "required": ["title", "start", "end"],
        },
    },
    {
        "type": "function",
        "name": "calendar_move",
        "description": "PROPOSE moving an existing calendar event (id from calendar_free_busy) to a new time. Does not write; returns an action_id the human must approve.",
        "parameters": {
            "type": "object",
            "properties": {
                "event_id": {"type": "string"},
                "new_start": {"type": "string", "description": _ISO},
                "new_end": {"type": "string", "description": _ISO + "; default keeps the duration"},
            },
            "required": ["event_id", "new_start"],
        },
    },
    {
        "type": "function",
        "name": "set_reminder",
        "description": "PROPOSE a reminder at a time. Does not write; returns an action_id the human must approve.",
        "parameters": {
            "type": "object",
            "properties": {"text": {"type": "string"}, "at": {"type": "string", "description": _ISO}},
            "required": ["text", "at"],
        },
    },
    {
        "type": "function",
        "name": "draft_message",
        "description": "PROPOSE a message to a contact from the profile (e.g. notify family). Only a draft; nothing is sent until the human approves.",
        "parameters": {
            "type": "object",
            "properties": {"contact": {"type": "string", "description": "Contact id or name"}, "body": {"type": "string"}},
            "required": ["contact", "body"],
        },
    },
    {
        "type": "function",
        "name": "respond",
        "description": "FINAL step, call exactly once after all other tools: one short spoken line plus the cards to show, picked from the client catalog. The server fills each card with trusted data.",
        "parameters": {
            "type": "object",
            "properties": {
                "say": {"type": "string", "description": "One short spoken sentence that directly answers the user"},
                "cards": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "component": {
                                "type": "string",
                                "enum": ["EventCard", "ConflictCard", "TrainCard", "ReminderCard", "MessageDraftCard", "ConfirmCard"],
                            },
                            "event": {
                                "type": "object",
                                "description": "EventCard: the event from the page",
                                "properties": {
                                    "title": {"type": "string"},
                                    "start": {"type": "string"},
                                    "end": {"type": "string"},
                                    "location": {"type": "string"},
                                },
                            },
                            "conflict_event_id": {"type": "string", "description": "ConflictCard: id of the conflicting calendar entry"},
                            "action_id": {"type": "string", "description": "Proposal shown on this card (move, add, reminder, message, confirm)"},
                            "title": {"type": "string", "description": "ConfirmCard: short label"},
                        },
                        "required": ["component"],
                    },
                },
            },
            "required": ["say", "cards"],
        },
    },
]


@dataclass
class RequestCtx:
    profile: Profile
    now: datetime
    locale: str
    url: str = ""
    proposals: list[PendingAction] = field(default_factory=list)
    conflicts: dict[str, dict[str, Any]] = field(default_factory=dict)
    busy_checked: list[tuple[datetime, datetime]] = field(default_factory=list)
    connections: dict[str, Any] | None = None
    slots: list[dict[str, Any]] | None = None
    event: dict[str, Any] | None = None


def _contact(profile: Profile, key: str):
    key_l = key.strip().lower()
    for c in profile.contacts:
        if key_l in {c.id.lower(), c.name.lower(), (c.relation or "").lower()}:
            return c
    return None


# ---------- read tools ----------


def calendar_free_busy(ctx: RequestCtx, start: str, end: str) -> dict[str, Any]:
    s, e = parse_dt(start), parse_dt(end)
    events = busy_and_conflicts(s, e, ME)
    ctx.busy_checked.append((s, e))
    for ev in events:
        ctx.conflicts[ev.id] = ev.to_json()
    return {"window": {"start": s.isoformat(), "end": e.isoformat()}, "free": not events, "busy": [ev.to_json() for ev in events]}


def sbb_connections(
    ctx: RequestCtx, origin: str, destination: str, datetime: str, is_arrival_time: bool = True, limit: int = 4
) -> dict[str, Any]:
    res = sbb.connections(origin, destination, parse_dt(datetime), is_arrival_time, limit)
    ctx.connections = res
    return res


def shared_free_slot(
    ctx: RequestCtx, participants: list[str], date: str, duration_min: int, earliest: str = "08:00", latest: str = "22:00"
) -> dict[str, Any]:
    owners = [ME]
    names = []
    for p in participants:
        c = _contact(ctx.profile, p)
        if c:
            owners.append(c.id)
            names.append(c.name)
    day = datetime.fromisoformat(date).date()
    start = datetime.combine(day, time.fromisoformat(earliest), ctx.now.tzinfo)
    end = datetime.combine(day, time.fromisoformat(latest), ctx.now.tzinfo)
    start = max(start, ctx.now.replace(second=0, microsecond=0))
    slots = free_slots(owners, start, end, timedelta(minutes=max(15, duration_min)))
    items = [{"start": a.isoformat(), "end": b.isoformat()} for a, b in slots[:6]]
    ctx.slots = items
    return {"participants": ["you", *names], "slots": items}


# ---------- write proposals ----------


def _propose(ctx: RequestCtx, tool: str, label: str, preview: str, ops: list[dict[str, Any]]) -> dict[str, Any]:
    act = store.add_action(tool, label, preview, ops)
    ctx.proposals.append(act)
    return {"status": "pending_human_confirmation", "action_id": act.id, "preview": preview}


def propose_calendar_create(ctx: RequestCtx, title: str, start: str, end: str, location: str | None = None, description: str | None = None):
    s, e = parse_dt(start), parse_dt(end)
    de = ctx.locale == "de"
    preview = f'{"Erstelle" if de else "Create"} "{title}" {day_label(s, ctx.locale)} {hm(s)}-{hm(e)}' + (f" ({location})" if location else "") + "."
    label = f"{'Eintragen' if de else 'Add'}: {title}"
    op = {"tool": "calendar_create", "args": {"title": title, "start": s.isoformat(), "end": e.isoformat(), "location": location, "description": description}}
    return _propose(ctx, "calendar_create", label, preview, [op])


def propose_calendar_move(ctx: RequestCtx, event_id: str, new_start: str, new_end: str | None = None):
    ev = get_calendar().get_event(event_id)
    if ev is None:
        return {"error": f"unknown event_id {event_id}; call calendar_free_busy first"}
    s = parse_dt(new_start)
    e = parse_dt(new_end) if new_end else s + (ev.end - ev.start)
    de = ctx.locale == "de"
    label = f'{"Verschiebe" if de else "Move"} {ev.title} {"auf" if de else "to"} {hm(s)}'
    preview = (
        f'{"Verschiebe" if de else "Move"} "{ev.title}" {"von" if de else "from"} {hm(ev.start)}-{hm(ev.end)} '
        f'{"auf" if de else "to"} {hm(s)}-{hm(e)} {"am" if de else "on"} {day_label(s, ctx.locale)}.'
    )
    op = {"tool": "calendar_move", "args": {"event_id": event_id, "new_start": s.isoformat(), "new_end": e.isoformat()}}
    return _propose(ctx, "calendar_move", label, preview, [op])


def propose_set_reminder(ctx: RequestCtx, text: str, at: str):
    a = parse_dt(at)
    de = ctx.locale == "de"
    label = f"{'Erinnerung' if de else 'Remind me'} {hm(a)}"
    preview = f'{"Erinnerung" if de else "Reminder"} "{text}" {day_label(a, ctx.locale)} {hm(a)}.'
    return _propose(ctx, "set_reminder", label, preview, [{"tool": "set_reminder", "args": {"text": text, "at": a.isoformat()}}])


def propose_draft_message(ctx: RequestCtx, contact: str, body: str):
    c = _contact(ctx.profile, contact)
    if c is None:
        return {"error": f"unknown contact {contact}; known: {[x.id for x in ctx.profile.contacts]}"}
    de = ctx.locale == "de"
    label = f"{'Senden an' if de else 'Send to'} {c.name}"
    preview = f'{"Sende an" if de else "Send to"} {c.name} ({c.channel}): "{body}"'
    return _propose(ctx, "draft_message", label, preview, [{"tool": "draft_message", "args": {"contact_id": c.id, "body": body}}])


def propose_calendar_bundle(ctx: RequestCtx, events: list[dict[str, Any]], label: str) -> PendingAction:
    """One approval for several calendar entries (e.g. the event plus the train to it)."""
    ops, lines = [], []
    for ev in events:
        s, e = parse_dt(ev["start"]), parse_dt(ev["end"])
        ops.append({"tool": "calendar_create", "args": {"title": ev["title"], "start": s.isoformat(), "end": e.isoformat(), "location": ev.get("location"), "description": ev.get("description")}})
        lines.append(f'"{ev["title"]}" {day_label(s, ctx.locale)} {hm(s)}-{hm(e)}')
    verb = "Erstelle" if ctx.locale == "de" else "Create"
    preview = f"{verb} " + (" + ".join(lines)) + "."
    act = store.add_action("calendar_create", label, preview, ops)
    ctx.proposals.append(act)
    return act


READ_DISPATCH = {"calendar_free_busy": calendar_free_busy, "sbb_connections": sbb_connections, "shared_free_slot": shared_free_slot}
WRITE_DISPATCH = {
    "calendar_create": propose_calendar_create,
    "calendar_move": propose_calendar_move,
    "set_reminder": propose_set_reminder,
    "draft_message": propose_draft_message,
}


def call_tool(ctx: RequestCtx, name: str, args: dict[str, Any]) -> dict[str, Any]:
    fn = READ_DISPATCH.get(name) or WRITE_DISPATCH.get(name)
    if fn is None:
        return {"error": f"unknown tool {name}"}
    try:
        return fn(ctx, **args)
    except Exception as exc:
        log.warning("tool %s failed: %s", name, exc)
        return {"error": f"{type(exc).__name__}: {exc}"}


# ---------- execution after /confirm ----------


def _deep_link(channel: str, address: str | None, body: str) -> str | None:
    if not address:
        return None
    if channel == "sms":
        return f"sms:{address}?&body={quote(body)}"
    if channel == "whatsapp":
        return f"https://wa.me/{address.lstrip('+')}?text={quote(body)}"
    return f"mailto:{address}?body={quote(body)}"


def execute_op(op: dict[str, Any], edits: dict[str, Any]) -> dict[str, Any]:
    tool, args = op["tool"], dict(op["args"])
    cal = get_calendar()
    if tool == "calendar_create":
        start = parse_dt(edits.get("start", args["start"]))
        end = parse_dt(edits.get("end", args["end"]))
        ev = cal.create_event(args["title"], start, end, args.get("location"), args.get("description"))
        return {"event": ev.to_json(), "message": f'Added "{ev.title}" {hm(ev.start)}-{hm(ev.end)}.'}
    if tool == "calendar_move":
        start = parse_dt(edits.get("start", args["new_start"]))
        end = parse_dt(edits.get("end", args["new_end"]))
        ev = cal.move_event(args["event_id"], start, end)
        return {"event": ev.to_json(), "message": f'Moved "{ev.title}" to {hm(ev.start)}-{hm(ev.end)}.'}
    if tool == "set_reminder":
        text = edits.get("text", args["text"])
        at = parse_dt(edits.get("at", args["at"]))
        ev = cal.create_event(f"Reminder: {text}", at, at + timedelta(minutes=5))
        reminder = {"text": text, "at": at.isoformat(), "event_id": ev.id}
        with store.lock:
            store.reminders.append(reminder)
        return {"reminder": reminder, "message": f'Reminder "{text}" set for {hm(at)}.'}
    if tool == "draft_message":
        c = _contact(store.profile, args["contact_id"])
        body = edits.get("body", args["body"])
        msg = {
            "to": {"name": c.name if c else args["contact_id"], "channel": c.channel if c else "sms", "address": c.address if c else None},
            "body": body,
            "sent_at": datetime.now().astimezone().isoformat(),
            "deep_link": _deep_link(c.channel, c.address, body) if c else None,
        }
        with store.lock:
            store.outbox.append(msg)
        return {"message_sent": msg, "message": f"Message to {msg['to']['name']} approved and queued."}
    raise ValueError(f"unknown write tool {tool}")
