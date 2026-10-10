"""Swiss train connections tool via transport.opendata.ch (contracts § Tools)."""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

import httpx

log = logging.getLogger(__name__)

TZ = ZoneInfo("Europe/Zurich")
SBB_URL = "https://transport.opendata.ch/v1/connections"


def compact(data: dict[str, Any]) -> dict[str, Any]:
    """transport.opendata.ch connections → the compact shape in contracts § Tools."""
    out = []
    for c in data.get("connections", [])[:4]:
        dep = c["from"]["departureTimestamp"]
        arr = c["to"]["arrivalTimestamp"]
        products = c.get("products") or []
        line = products[0] if products else ""
        out.append(
            {
                "line": line,
                "from": c["from"]["station"]["name"],
                "to": c["to"]["station"]["name"],
                "departure": datetime.fromtimestamp(dep, TZ).isoformat(),
                "arrival": datetime.fromtimestamp(arr, TZ).isoformat(),
                "platform": c["from"].get("platform"),
                "arrival_platform": c["to"].get("platform"),
                "transfers": c.get("transfers", 0),
                "delay_min": c["from"].get("delay") or 0,
                "duration_min": (arr - dep) // 60,
            }
        )
    return {"connections": out}


async def sbb_connections(
    from_station: str,
    to_station: str,
    depart_after: str,
    timeout: float = 5.0,
    client: httpx.AsyncClient | None = None,
) -> dict[str, Any]:
    """Fetch public transport connections departing after the given time (ISO 8601)."""
    when = datetime.fromisoformat(depart_after)
    when = when.astimezone(TZ) if when.tzinfo else when.replace(tzinfo=TZ)
    params = {
        "from": from_station,
        "to": to_station,
        "date": f"{when:%Y-%m-%d}",
        "time": f"{when:%H:%M}",
        "limit": 4,
    }
    if client is not None:
        r = await client.get(SBB_URL, params=params)
        r.raise_for_status()
        return compact(r.json())

    async with httpx.AsyncClient(timeout=timeout) as http:
        r = await http.get(SBB_URL, params=params)
        r.raise_for_status()
        return compact(r.json())


def sbb_connections_sync(
    from_station: str,
    to_station: str,
    depart_after: str,
    timeout: float = 5.0,
) -> dict[str, Any]:
    """Synchronous version of sbb_connections."""
    return asyncio.run(sbb_connections(from_station, to_station, depart_after, timeout=timeout))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Query SBB connections")
    parser.add_argument("from_station", nargs="?", default="Zürich HB")
    parser.add_argument("to_station", nargs="?", default="Bern")
    parser.add_argument("depart_after", nargs="?", default="2026-10-15T17:55:00+02:00")
    args = parser.parse_args()

    result = sbb_connections_sync(args.from_station, args.to_station, args.depart_after)
    print(json.dumps(result, indent=2, ensure_ascii=False))
