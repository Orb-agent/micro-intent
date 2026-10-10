"""Swiss public transport connections via transport.opendata.ch, with a scripted timetable fallback."""

from __future__ import annotations

import logging
from datetime import datetime, timedelta

import httpx

from .config import settings

log = logging.getLogger(__name__)

API = "https://transport.opendata.ch/v1/connections"
# Preference tiers for the recommended connection: intercity first, then regional express.
TIERS = (("IC", "EC", "ICE"), ("IR", "RE"))

# Typical Winterthur -> Zürich HB pattern per hour: (product, minute, duration_min, platform).
_SCRIPTED_PATTERN = [("IR 75", 1, 25, "4"), ("S11", 9, 19, "3"), ("IR 13", 24, 28, "3"), ("IC 8", 31, 26, "4"), ("S12", 52, 20, "7")]


def _parse_ts(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%S%z").astimezone(settings.tz)


def _simplify(conn: dict) -> dict:
    dep = _parse_ts(conn["from"]["departure"])
    arr = _parse_ts(conn["to"]["arrival"])
    return {
        "departure": dep.isoformat(),
        "arrival": arr.isoformat(),
        "duration_min": int((arr - dep).total_seconds() // 60),
        "transfers": conn.get("transfers", 0),
        "products": list(conn.get("products") or []),
        "platform": conn["from"].get("platform"),
        "from_station": conn["from"]["station"]["name"],
        "to_station": conn["to"]["station"]["name"],
    }


def _mark_recommended(items: list[dict], when: datetime, is_arrival_time: bool) -> list[dict]:
    if not items:
        return items
    if is_arrival_time:
        on_time = [c for c in items if datetime.fromisoformat(c["arrival"]) <= when] or items
        pool = on_time
        for tier in TIERS:
            tiered = [c for c in on_time if any(p.split(" ")[0] in tier for p in c["products"])]
            if tiered:
                pool = tiered
                break
        best = max(pool, key=lambda c: c["departure"])
    else:
        best = items[0]
    for c in items:
        c["recommended"] = c is best
    return items


def scripted_connections(origin: str, destination: str, when: datetime, is_arrival_time: bool, limit: int) -> list[dict]:
    """Plausible Winterthur -> Zürich timetable used when the live API is unreachable."""
    base = when.replace(minute=0, second=0, microsecond=0)
    items = []
    for hour_offset in (-2, -1, 0, 1):
        for product, minute, dur, platform in _SCRIPTED_PATTERN:
            dep = base + timedelta(hours=hour_offset, minutes=minute)
            items.append(
                {
                    "departure": dep.isoformat(),
                    "arrival": (dep + timedelta(minutes=dur)).isoformat(),
                    "duration_min": dur,
                    "transfers": 0,
                    "products": [product],
                    "platform": platform,
                    "from_station": origin,
                    "to_station": destination,
                }
            )
    items.sort(key=lambda c: c["departure"])
    if is_arrival_time:
        items = [c for c in items if datetime.fromisoformat(c["arrival"]) <= when][-limit:]
    else:
        items = [c for c in items if datetime.fromisoformat(c["departure"]) >= when][:limit]
    return _mark_recommended(items, when, is_arrival_time)


def connections(origin: str, destination: str, when: datetime, is_arrival_time: bool = True, limit: int = 4) -> dict:
    """Connections around `when`; `source` is "live" or "scripted" (fallback)."""
    limit = max(1, min(limit, 6))
    when = when.astimezone(settings.tz)
    params = {
        "from": origin,
        "to": destination,
        "date": when.strftime("%Y-%m-%d"),
        "time": when.strftime("%H:%M"),
        "isArrivalTime": 1 if is_arrival_time else 0,
        "limit": limit if not is_arrival_time else limit + 2,
    }
    try:
        resp = httpx.get(API, params=params, timeout=settings.sbb_timeout_s)
        resp.raise_for_status()
        raw = resp.json().get("connections") or []
        items = [_simplify(c) for c in raw]
        if is_arrival_time:
            items = [c for c in items if datetime.fromisoformat(c["arrival"]) <= when][-limit:] or items[:limit]
        else:
            items = items[:limit]
        if not items:
            raise ValueError("no connections returned")
        return {
            "from": items[0]["from_station"],
            "to": items[0]["to_station"],
            "source": "live",
            "items": _mark_recommended(items, when, is_arrival_time),
        }
    except Exception as exc:
        log.warning("SBB lookup failed (%s -> %s), using scripted timetable: %s", origin, destination, exc)
        return {
            "from": origin,
            "to": destination,
            "source": "scripted",
            "items": scripted_connections(origin, destination, when, is_arrival_time, limit),
        }


def route_url(origin: str, destination: str) -> str:
    return str(
        httpx.URL(
            "https://www.google.com/maps/dir/",
            params={"api": 1, "origin": origin, "destination": destination, "travelmode": "transit"},
        )
    )
