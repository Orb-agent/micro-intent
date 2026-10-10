"""A2UI v0.9 basic catalog message generator for card replies (contracts § A2UI)."""

from __future__ import annotations

import re
from datetime import datetime
from typing import Any
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo

TZ = ZoneInfo("Europe/Zurich")
CATALOG_ID = "https://a2ui.org/specification/v0_9/basic_catalog.json"
VERSION = "v0.9"


def _local(iso_str: str) -> datetime | None:
    try:
        dt = datetime.fromisoformat(iso_str)
    except ValueError:
        return None
    return dt.replace(tzinfo=TZ) if dt.tzinfo is None else dt.astimezone(TZ)


def _format_hm(iso_str: str) -> str:
    """Format an ISO 8601 timestamp as HH:MM in Europe/Zurich."""
    dt = _local(iso_str)
    return dt.strftime("%H:%M") if dt else iso_str


def _format_day(iso_str: str) -> str:
    """'Sat 17 Oct' in Europe/Zurich: event and flight cards are often about another day."""
    dt = _local(iso_str)
    return f"{dt:%a} {dt.day} {dt:%b}" if dt else ""


VERDICTS = {"fits": "You can make it", "tight": "Tight, but you can make it", "clash": "That clashes"}


def _train_components(idx: int, card: dict[str, Any]) -> list[dict[str, Any]]:
    dep = _format_hm(str(card.get("departure", "")))
    arr = _format_hm(str(card.get("arrival", "")))
    line = card.get("line", "")
    from_st = card.get("from", "")
    to_st = card.get("to", "")

    meta_parts: list[str] = []
    if card.get("platform"):
        meta_parts.append(f"Platform {card['platform']}")
    transfers = card.get("transfers", 0)
    meta_parts.append("direct" if transfers == 0 else f"{transfers} transfer(s)")
    if card.get("delay_min"):
        meta_parts.append(f"+{card['delay_min']} min")
    meta_text = " · ".join(meta_parts)

    body_id = f"c{idx}-body"
    time_id = f"c{idx}-time"
    line_id = f"c{idx}-line"
    meta_id = f"c{idx}-meta"

    children = [time_id, line_id]
    components = [
        {"id": f"c{idx}", "component": "Card", "child": body_id},
        {"id": body_id, "component": "Column", "children": children},
        {"id": time_id, "component": "Text", "text": f"{dep} → {arr}", "variant": "h2"},
        {"id": line_id, "component": "Text", "text": f"{line} · {from_st} → {to_st}"},
    ]
    if meta_text:
        children.append(meta_id)
        components.append({"id": meta_id, "component": "Text", "text": meta_text, "variant": "caption"})

    return components


def _conflict_components(idx: int, card: dict[str, Any]) -> list[dict[str, Any]]:
    event = card.get("event") or {}
    proposal = card.get("proposal") or {}
    verdict = card.get("verdict", "")
    note = card.get("note")

    ev_title = event.get("title", "")
    ev_start = _format_hm(str(event.get("start", "")))
    ev_end = _format_hm(str(event.get("end", "")))

    prop_title = proposal.get("title", "")
    prop_start = _format_hm(str(proposal.get("start", "")))
    prop_place = f" · {proposal['place']}" if proposal.get("place") else ""

    body_id = f"c{idx}-body"
    verdict_id = f"c{idx}-verdict"
    ev_id = f"c{idx}-event"
    prop_id = f"c{idx}-proposal"
    note_id = f"c{idx}-note"

    children = [verdict_id, ev_id, prop_id]
    components = [
        {"id": f"c{idx}", "component": "Card", "child": body_id},
        {"id": body_id, "component": "Column", "children": children},
        {"id": verdict_id, "component": "Text", "text": VERDICTS.get(verdict, f"Plan check · {verdict}"), "variant": "h2"},
        {"id": ev_id, "component": "Text", "text": f"{ev_title} · {ev_start}–{ev_end}"},
        {"id": prop_id, "component": "Text", "text": f"{prop_title} · {prop_start}{prop_place}"},
    ]
    if note:
        children.append(note_id)
        components.append({"id": note_id, "component": "Text", "text": str(note), "variant": "caption"})

    return components


def _event_components(idx: int, card: dict[str, Any]) -> list[dict[str, Any]]:
    title = card.get("title", "")
    start, end = str(card.get("start", "")), str(card.get("end", ""))
    start_day, end_day = _format_day(start), _format_day(end)
    if start_day != end_day:
        when = f"{start_day} {_format_hm(start)} → {end_day} {_format_hm(end)}"
    else:
        when = " · ".join(filter(None, [start_day, f"{_format_hm(start)}–{_format_hm(end)}"]))
    location = card.get("location")
    source = "Luma" if card.get("source") == "luma" else "Calendar"

    meta = f"{location} · {source}" if location else source

    body_id = f"c{idx}-body"
    title_id = f"c{idx}-title"
    time_id = f"c{idx}-time"
    meta_id = f"c{idx}-meta"

    children = [title_id, time_id, meta_id]
    return [
        {"id": f"c{idx}", "component": "Card", "child": body_id},
        {"id": body_id, "component": "Column", "children": children},
        {"id": title_id, "component": "Text", "text": str(title), "variant": "h2"},
        {"id": time_id, "component": "Text", "text": when},
        {"id": meta_id, "component": "Text", "text": meta, "variant": "caption"},
    ]


def _flight_components(idx: int, card: dict[str, Any]) -> list[dict[str, Any]]:
    from_code = card.get("from", "")
    to_code = card.get("to", "")
    flight_num = card.get("flight_number", "")
    departure = str(card.get("departure", ""))
    dep = _format_hm(departure)
    arr = _format_hm(str(card.get("arrival", "")))
    booking_ref = card.get("booking_ref")
    meta_text = " · ".join(filter(None, [_format_day(departure), booking_ref and f"Booking {booking_ref}"]))

    body_id = f"c{idx}-body"
    time_id = f"c{idx}-time"
    line_id = f"c{idx}-line"
    meta_id = f"c{idx}-meta"

    children = [time_id, line_id]
    components = [
        {"id": f"c{idx}", "component": "Card", "child": body_id},
        {"id": body_id, "component": "Column", "children": children},
        {"id": time_id, "component": "Text", "text": f"{dep} → {arr}", "variant": "h2"},
        {"id": line_id, "component": "Text", "text": f"{flight_num} · {from_code} → {to_code}"},
    ]
    if meta_text:
        children.append(meta_id)
        components.append({"id": meta_id, "component": "Text", "text": meta_text, "variant": "caption"})

    return components


def _link_components(idx: int, card: dict[str, Any]) -> list[dict[str, Any]]:
    """A titled link, e.g. a prefilled Google Flights search. a2ui-swift renders inline Markdown
    in Text, so the caption is a tappable link; only https links become one."""
    url = str(card.get("url", ""))
    children = [f"c{idx}-title"]
    components = [
        {"id": f"c{idx}", "component": "Card", "child": f"c{idx}-body"},
        {"id": f"c{idx}-body", "component": "Column", "children": children},
        {"id": f"c{idx}-title", "component": "Text", "text": str(card.get("title", "")), "variant": "h2"},
    ]
    if card.get("detail"):
        children.append(f"c{idx}-detail")
        components.append({"id": f"c{idx}-detail", "component": "Text", "text": str(card["detail"])})
    if url.startswith("https://") and not re.search(r"[\s()<>]", url):
        host = urlsplit(url).hostname or url
        label = "Open in Google Flights" if host == "www.google.com" and urlsplit(url).path.startswith("/travel/flights") else f"Open {host}"
        children.append(f"c{idx}-meta")
        components.append({"id": f"c{idx}-meta", "component": "Text", "text": f"[{label}]({url})", "variant": "caption"})
    return components


def cards_to_a2ui(reply_id: str, cards: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Convert reply cards into A2UI v0.9 basic catalog messages (contracts § A2UI)."""
    card_ids = [f"c{i}" for i in range(len(cards))]
    root_component: dict[str, Any] = {"id": "root", "component": "Column", "children": card_ids}

    components: list[dict[str, Any]] = [root_component]

    for i, card in enumerate(cards):
        kind = card.get("kind")
        if kind == "train":
            components.extend(_train_components(i, card))
        elif kind == "conflict":
            components.extend(_conflict_components(i, card))
        elif kind == "event":
            components.extend(_event_components(i, card))
        elif kind == "flight":
            components.extend(_flight_components(i, card))
        elif kind == "link":
            components.extend(_link_components(i, card))
        else:
            # Fallback for unrecognized card kind
            body_id = f"c{i}-body"
            text_id = f"c{i}-text"
            components.extend([
                {"id": f"c{i}", "component": "Card", "child": body_id},
                {"id": body_id, "component": "Column", "children": [text_id]},
                {"id": text_id, "component": "Text", "text": str(card)},
            ])

    return [
        {"version": VERSION, "createSurface": {"surfaceId": reply_id, "catalogId": CATALOG_ID}},
        {"version": VERSION, "updateComponents": {"surfaceId": reply_id, "components": components}},
    ]
