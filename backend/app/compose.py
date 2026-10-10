"""Turn the agent's card choices into A2UI surfaces filled with server-side (trusted) data.

The agent only picks catalog components and references; times, trains, conflicts and write previews come from tools.
Every write proposal ends up on exactly one card, so nothing can be confirmed that the user did not see.
"""

from __future__ import annotations

from datetime import datetime, time, timedelta
from typing import Any

from . import a2ui
from .calendar_source import ME, CalEvent, busy_and_conflicts, free_slots, get_calendar, overlaps
from .fmt import ceil_quarter, parse_dt
from .sbb import route_url
from .state import PendingAction, new_id, store
from .tools import RequestCtx, propose_calendar_bundle, propose_calendar_move

_TEXT = {
    "add": {"en": "Add to calendar", "de": "In Kalender eintragen"},
    "confirm": {"en": "Confirm", "de": "Bestätigen"},
}


def _t(key: str, locale: str) -> str:
    return _TEXT[key].get(locale, _TEXT[key]["en"])


def _event_window(ev: dict[str, Any] | None) -> tuple[datetime, datetime] | None:
    if not ev or not ev.get("start"):
        return None
    try:
        start = parse_dt(ev["start"])
        end = parse_dt(ev["end"]) if ev.get("end") else start + timedelta(hours=2)
    except ValueError:
        return None
    return start, max(end, start + timedelta(minutes=15))


def _norm(title: str) -> str:
    return "".join(ch for ch in title.lower() if ch.isalnum())


def _is_same_event(ev: dict[str, Any], window: tuple[datetime, datetime], entry: CalEvent) -> bool:
    a, b = _norm(ev.get("title") or ""), _norm(entry.title)
    return entry.start == window[0] and bool(a) and bool(b) and (a in b or b in a)


def split_calendar(ev: dict[str, Any], window: tuple[datetime, datetime]) -> tuple[list[CalEvent], bool]:
    """Conflicting entries in the event window, and whether the event itself is already in the calendar."""
    entries = busy_and_conflicts(*window, ME)
    already = any(_is_same_event(ev, window, e) for e in entries)
    conflicts = [e for e in entries if not _is_same_event(ev, window, e) and overlaps(e.start, e.end, *window)]
    return conflicts, already


def _recommended_departure(ctx: RequestCtx) -> datetime | None:
    items = (ctx.connections or {}).get("items") or []
    rec = next((c for c in items if c.get("recommended")), items[0] if items else None)
    return parse_dt(rec["departure"]) if rec else None


def suggest_move(ctx: RequestCtx, conflict: CalEvent, window: tuple[datetime, datetime] | None) -> PendingAction | None:
    """Propose moving `conflict` to the latest free slot before the user leaves, else the first one after the event."""
    duration = conflict.end - conflict.start
    day = conflict.start.date()
    tz = conflict.start.tzinfo
    floor = ceil_quarter(max(datetime.combine(day, time(8, 0), tz), ctx.now))
    quarter = timedelta(minutes=15)
    latest_end = min(filter(None, [_recommended_departure(ctx), window[0] if window else None, conflict.start]))
    before = [s for s in free_slots([ME], floor, latest_end, duration, quarter) if s[1] <= latest_end]
    if before:
        slot = before[-1]
    else:
        after_start = ceil_quarter(max(window[1] if window else conflict.end, floor))
        after = free_slots([ME], after_start, datetime.combine(day, time(22, 0), tz), duration, quarter)
        if not after:
            return None
        slot = after[0]
    res = propose_calendar_move(ctx, conflict.id, slot[0].isoformat(), slot[1].isoformat())
    return next((p for p in ctx.proposals if p.id == res.get("action_id")), None)


class TurnBuilder:
    def __init__(self, ctx: RequestCtx, turn_id: str) -> None:
        self.ctx = ctx
        self.turn_id = turn_id
        self.messages: list[dict[str, Any]] = []
        self.used: set[str] = set()
        self.components: list[str] = []
        self.conflict_ids: set[str] = set()

    # ---- helpers ----

    def _proposal(self, action_id: str | None, tools: set[str], pred=None) -> PendingAction | None:
        cands = [p for p in self.ctx.proposals if p.id not in self.used and p.tool in tools and (pred is None or pred(p))]
        chosen = next((p for p in cands if p.id == action_id), None) or (cands[0] if cands else None)
        if chosen:
            self.used.add(chosen.id)
        return chosen

    def _add(self, component: str, props: dict[str, Any], actions: list[PendingAction], data: dict[str, Any] | None = None) -> str:
        sid = f"{self.turn_id}_{component[:-4].lower()}_{len(self.components)}"
        for a in actions:
            a.surface_id = sid
            a.turn_id = self.turn_id
        self.components.append(component)
        self.messages.extend(a2ui.surface(sid, component, props, data))
        return sid

    # ---- cards ----

    def event_card(self, ev: dict[str, Any], action_id: str | None = None) -> None:
        window = _event_window(ev)
        if not window or "EventCard" in self.components:
            return
        conflicts, already = split_calendar(ev, window)
        props: dict[str, Any] = {
            "title": ev.get("title") or "Event",
            "start": window[0].isoformat(),
            "end": window[1].isoformat(),
            "availability": "conflict" if conflicts else "free",
            "inCalendar": already,
        }
        if ev.get("location"):
            props["location"] = ev["location"]
        if self.ctx.url:
            props["url"] = self.ctx.url
        add = self._proposal(action_id, {"calendar_create"}) or (None if already else self._auto_add(ev, window))
        if add:
            props["addAction"] = {"label": add.label, "preview": add.preview, **a2ui.event_action("confirm", action_id=add.id)}
        sid = self._add("EventCard", props, [add] if add else [])
        with store.lock:
            store.event_cards[self.turn_id] = {"surface_id": sid, "props": props, "event": ev}

    def _auto_add(self, ev: dict[str, Any], window: tuple[datetime, datetime]) -> PendingAction:
        """Offer to put the event, plus the recommended train when there is one, into the calendar."""
        de = self.ctx.locale == "de"
        entries = [{"title": ev.get("title") or "Event", "start": window[0], "end": window[1], "location": ev.get("location")}]
        conn = self.ctx.connections or {}
        train = next((c for c in conn.get("items") or [] if c.get("recommended")), None)
        if train:
            product = (train.get("products") or ["Train"])[0]
            entries.append({"title": f"{product} {conn['from']} → {conn['to']}", "start": train["departure"], "end": train["arrival"]})
            label = "Event + Zug eintragen" if de else "Add event + train"
        else:
            label = _t("add", self.ctx.locale)
        act = propose_calendar_bundle(self.ctx, entries, label)
        self.used.add(act.id)
        return act

    def conflict_card(self, event_id: str | None, action_id: str | None = None) -> None:
        conflict = get_calendar().get_event(event_id) if event_id else None
        ev = self.ctx.event or {}
        window = _event_window(ev)
        if conflict is None or conflict.id in self.conflict_ids or (window and _is_same_event(ev, window, conflict)):
            return
        self.conflict_ids.add(conflict.id)
        move = self._proposal(action_id, {"calendar_move"}, lambda p: p.ops[0]["args"]["event_id"] == conflict.id)
        if move is None:
            move = suggest_move(self.ctx, conflict, window)
            if move:
                self.used.add(move.id)
        props: dict[str, Any] = {
            "conflict": {
                "eventId": conflict.id,
                "title": conflict.title,
                "start": conflict.start.isoformat(),
                "end": conflict.end.isoformat(),
                "calendar": conflict.calendar,
            },
            "eventTitle": ev.get("title") or "",
        }
        ref = move.id if move else ""
        if move:
            args = move.ops[0]["args"]
            props["move"] = {
                "label": move.label,
                "preview": move.preview,
                "newStart": args["new_start"],
                "newEnd": args["new_end"],
                "action": a2ui.event_action("confirm", action_id=move.id),
            }
        props["skipAction"] = a2ui.event_action("skip", action_id=ref)
        props["keepAction"] = a2ui.event_action("keep", action_id=ref)
        self._add("ConflictCard", props, [move] if move else [])

    def train_card(self) -> None:
        conn = self.ctx.connections
        if not conn or not conn.get("items") or "TrainCard" in self.components:
            return
        props = {
            "from": conn["from"],
            "to": conn["to"],
            "live": conn.get("source") == "live",
            "connections": [
                {
                    "departure": c["departure"],
                    "arrival": c["arrival"],
                    "durationMin": c.get("duration_min"),
                    "transfers": c.get("transfers", 0),
                    "products": c.get("products") or [],
                    "platform": c.get("platform"),
                    "recommended": bool(c.get("recommended")),
                }
                for c in conn["items"][:4]
            ],
            "openAction": a2ui.open_url_action(route_url(conn["from"], conn["to"])),
        }
        self._add("TrainCard", props, [])

    def reminder_card(self, action_id: str | None = None) -> None:
        p = self._proposal(action_id, {"set_reminder"})
        if p:
            args = p.ops[0]["args"]
            props = {
                "text": args["text"],
                "at": args["at"],
                "preview": p.preview,
                "confirmAction": a2ui.event_action("confirm", action_id=p.id),
                "rejectAction": a2ui.event_action("reject", action_id=p.id),
            }
            self._add("ReminderCard", props, [p])

    def message_card(self, action_id: str | None = None) -> None:
        p = self._proposal(action_id, {"draft_message"})
        if not p:
            return
        args = p.ops[0]["args"]
        c = next((x for x in self.ctx.profile.contacts if x.id == args["contact_id"]), None)
        props = {
            "to": {"name": c.name, "relation": c.relation, "channel": c.channel} if c else {"name": args["contact_id"]},
            "body": {"path": "/draft/body"},
            "preview": p.preview,
            "sendAction": a2ui.event_action("confirm", action_id=p.id, body={"path": "/draft/body"}),
            "discardAction": a2ui.event_action("reject", action_id=p.id),
        }
        self._add("MessageDraftCard", props, [p], data={"draft": {"body": args["body"]}})

    def confirm_card(self, action_id: str | None = None, title: str | None = None) -> None:
        p = self._proposal(action_id, {"calendar_create", "calendar_move"})
        if not p:
            return
        props = {
            "title": title or (_t("add", self.ctx.locale) if p.tool == "calendar_create" else p.label),
            "preview": p.preview,
            "tool": p.tool,
            "confirmAction": a2ui.event_action("confirm", action_id=p.id),
            "rejectAction": a2ui.event_action("reject", action_id=p.id),
        }
        self._add("ConfirmCard", props, [p])

    # ---- assembly ----

    def build(self, choices: list[dict[str, Any]]) -> list[dict[str, Any]]:
        for ch in choices:
            comp = ch.get("component")
            if comp == "EventCard":
                ev = ch.get("event") or self.ctx.event
                if ev and not self.ctx.event:
                    self.ctx.event = ev
                if ev:
                    self.event_card(ev, ch.get("action_id"))
            elif comp == "ConflictCard":
                self.conflict_card(ch.get("conflict_event_id"), ch.get("action_id"))
            elif comp == "TrainCard":
                self.train_card()
            elif comp == "ReminderCard":
                self.reminder_card(ch.get("action_id"))
            elif comp == "MessageDraftCard":
                self.message_card(ch.get("action_id"))
            elif comp == "ConfirmCard":
                self.confirm_card(ch.get("action_id"), ch.get("title"))

        # Guarantees independent of the model: every conflict, the trains and every proposal get a card.
        window = _event_window(self.ctx.event)
        if window:
            for c in split_calendar(self.ctx.event, window)[0]:
                self.conflict_card(c.id)
        self.train_card()
        for p in list(self.ctx.proposals):
            if p.id not in self.used:
                {"set_reminder": self.reminder_card, "draft_message": self.message_card}.get(p.tool, self.confirm_card)(p.id)
        return self.messages


def refresh_event_card(turn_id: str | None, deleted_surface: str | None) -> list[dict[str, Any]]:
    """After a confirmed write, re-check the turn's EventCard against the calendar and update it in place."""
    rec = store.event_cards.get(turn_id or "")
    if not rec or rec["surface_id"] == deleted_surface:
        return []
    window = _event_window(rec["event"])
    if not window:
        return []
    conflicts, already = split_calendar(rec["event"], window)
    props = dict(rec["props"], availability="conflict" if conflicts else "free", inCalendar=already)
    add_id = (props.get("addAction") or {}).get("event", {}).get("context", {}).get("action_id")
    add = store.get_action(add_id) if add_id else None
    if already or (add_id and (add is None or add.status != "pending")):
        props.pop("addAction", None)
    rec["props"] = props
    return [
        {
            "version": a2ui.VERSION,
            "updateComponents": {"surfaceId": rec["surface_id"], "components": [{"id": "root", "component": "EventCard", **props}]},
        }
    ]


def build_turn(ctx: RequestCtx, say: str, choices: list[dict[str, Any]], source: str) -> dict[str, Any]:
    turn_id = new_id("turn")
    cards = TurnBuilder(ctx, turn_id).build(choices)
    return {"turn_id": turn_id, "say": say.strip(), "source": source, "cards": cards}


def plain_turn(say: str, source: str = "agent", cards: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    return {"turn_id": new_id("turn"), "say": say, "source": source, "cards": cards or []}
