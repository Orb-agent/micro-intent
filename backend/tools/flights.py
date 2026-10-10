"""Flight search (contracts § Tools): live Google Flights results through SerpApi when
SERPAPI_API_KEY is set; without it, only a prefilled Google Flights link, never made-up flights.
Read-only. Airline and airport names are third-party data.

Live smoke test, from backend/:
    uv run python -m tools.flights ZRH LIS 2026-10-20
"""

from __future__ import annotations

import argparse
import logging
import os
import re
from datetime import datetime
from typing import Any
from urllib.parse import quote
from zoneinfo import ZoneInfo

import httpx

from tools import google_auth

SERPAPI_URL = "https://serpapi.com/search.json"
MAX_FLIGHTS = 4
IATA = re.compile(r"[A-Z]{3}")
SECRET = re.compile(r"api_key=[^&\s'\"]+")


class _RedactKey(logging.Filter):
    """httpx logs every request URL at INFO, and SerpApi only takes the key in the URL."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.msg = SECRET.sub("api_key=***", str(record.msg))
        if isinstance(record.args, tuple):
            record.args = tuple(
                SECRET.sub("api_key=***", str(a)) if isinstance(a, (str, httpx.URL)) else a for a in record.args
            )
        return True


logging.getLogger("httpx").addFilter(_RedactKey())

# SerpApi gives local airport times without an offset; cards need one. Unknown airports keep
# the bare local time, and the agent leaves those flights out of cards.
AIRPORT_TZ = {
    **dict.fromkeys(["ZRH", "GVA", "BSL"], "Europe/Zurich"),
    **dict.fromkeys(["LIS", "OPO", "FAO"], "Europe/Lisbon"),
    **dict.fromkeys(["LHR", "LGW", "LCY", "STN", "LTN", "MAN", "EDI"], "Europe/London"),
    **dict.fromkeys(["DUB"], "Europe/Dublin"),
    **dict.fromkeys(["CDG", "ORY", "NCE", "LYS", "MRS"], "Europe/Paris"),
    **dict.fromkeys(["FRA", "MUC", "BER", "HAM", "DUS", "STR", "CGN"], "Europe/Berlin"),
    **dict.fromkeys(["AMS"], "Europe/Amsterdam"),
    **dict.fromkeys(["BRU"], "Europe/Brussels"),
    **dict.fromkeys(["VIE"], "Europe/Vienna"),
    **dict.fromkeys(["MAD", "BCN", "AGP", "PMI", "VLC", "SVQ"], "Europe/Madrid"),
    **dict.fromkeys(["FCO", "MXP", "LIN", "VCE", "NAP", "BLQ"], "Europe/Rome"),
    **dict.fromkeys(["CPH"], "Europe/Copenhagen"),
    **dict.fromkeys(["ARN"], "Europe/Stockholm"),
    **dict.fromkeys(["OSL"], "Europe/Oslo"),
    **dict.fromkeys(["HEL"], "Europe/Helsinki"),
    **dict.fromkeys(["WAW"], "Europe/Warsaw"),
    **dict.fromkeys(["PRG"], "Europe/Prague"),
    **dict.fromkeys(["BUD"], "Europe/Budapest"),
    **dict.fromkeys(["ATH"], "Europe/Athens"),
    **dict.fromkeys(["IST", "SAW"], "Europe/Istanbul"),
    **dict.fromkeys(["DXB"], "Asia/Dubai"),
    **dict.fromkeys(["DOH"], "Asia/Qatar"),
    **dict.fromkeys(["SIN"], "Asia/Singapore"),
    **dict.fromkeys(["HND", "NRT"], "Asia/Tokyo"),
    **dict.fromkeys(["JFK", "EWR", "BOS"], "America/New_York"),
    **dict.fromkeys(["ORD"], "America/Chicago"),
    **dict.fromkeys(["SFO", "LAX", "SEA"], "America/Los_Angeles"),
}


def google_flights_url(origin: str, destination: str, departure_date: str, return_date: str | None = None) -> str:
    """A Google Flights search prefilled from a sentence, which Google Flights parses itself."""
    if return_date:
        text = f"Flights from {origin} to {destination} on {departure_date} through {return_date}"
    else:  # without "one way" Google Flights opens a round trip
        text = f"One way flights from {origin} to {destination} on {departure_date}"
    return f"https://www.google.com/travel/flights?q={quote(text)}"


def _local_iso(airport: dict[str, Any]) -> str:
    """'2026-10-20 07:10' at ZRH → '2026-10-20T07:10:00+02:00'."""
    when = datetime.strptime(airport["time"], "%Y-%m-%d %H:%M")
    tz = AIRPORT_TZ.get(airport.get("id", ""))
    return when.replace(tzinfo=ZoneInfo(tz)).isoformat() if tz else when.isoformat()


def compact(data: dict[str, Any]) -> list[dict[str, Any]]:
    """SerpApi google_flights → flights in the shape of a flight card plus price and stops."""
    out = []
    for option in [*data.get("best_flights", []), *data.get("other_flights", [])][:MAX_FLIGHTS]:
        legs = option.get("flights") or []
        if not legs:
            continue
        first, last = legs[0], legs[-1]
        flight: dict[str, Any] = {
            "flight_number": first.get("flight_number", ""),
            "airline": first.get("airline", ""),
            "from": first["departure_airport"].get("id", ""),
            "to": last["arrival_airport"].get("id", ""),
            "departure": _local_iso(first["departure_airport"]),
            "arrival": _local_iso(last["arrival_airport"]),
            "stops": len(legs) - 1,
            "duration_min": option.get("total_duration"),
        }
        if option.get("price") is not None:
            flight["price_chf"] = option["price"]
        out.append(flight)
    return out


async def flights_search(
    origin: str,
    destination: str,
    departure_date: str,
    return_date: str | None = None,
    client: httpx.AsyncClient | None = None,
) -> dict[str, Any]:
    """Flights from origin to destination (IATA codes) on a date (YYYY-MM-DD), at most 4, and a
    Google Flights link for the same search. Without SERPAPI_API_KEY only the link."""
    origin, destination = origin.strip().upper(), destination.strip().upper()
    datetime.strptime(departure_date, "%Y-%m-%d")  # ValueError for anything else
    if return_date:
        datetime.strptime(return_date, "%Y-%m-%d")
    link = google_flights_url(origin, destination, departure_date, return_date)
    key = os.environ.get("SERPAPI_API_KEY")
    if not key:
        return {"flights": [], "google_flights_url": link, "note": "live flight search is not configured; offer the link"}
    if not (IATA.fullmatch(origin) and IATA.fullmatch(destination)):
        raise ValueError("origin and destination must be IATA airport codes, e.g. ZRH")
    if client is None:
        async with httpx.AsyncClient(timeout=google_auth.TIMEOUT) as http:
            return await flights_search(origin, destination, departure_date, return_date, http)
    params = {
        "engine": "google_flights",
        "departure_id": origin,
        "arrival_id": destination,
        "outbound_date": departure_date,
        "type": 1 if return_date else 2,  # round trip or one way
        "currency": "CHF",
        "hl": "en",
        "api_key": key,  # SerpApi only takes the key as a query parameter
    }
    if return_date:
        params["return_date"] = return_date
    r = await client.get(SERPAPI_URL, params=params)
    try:
        data = r.json()
    except ValueError:
        data = {}
    if r.is_error or data.get("error"):  # never raise_for_status: its message carries the URL with the key
        raise ValueError(f"SerpApi HTTP {r.status_code}: {data.get('error', 'no details')}")
    return {"flights": compact(data), "google_flights_url": data.get("search_metadata", {}).get("google_flights_url") or link}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Live smoke test for flights_search")
    parser.add_argument("origin", nargs="?", default="ZRH")
    parser.add_argument("destination", nargs="?", default="LIS")
    parser.add_argument("departure_date", nargs="?", default="2026-10-20")
    parser.add_argument("return_date", nargs="?")
    args = parser.parse_args()
    google_auth.smoke(lambda: flights_search(args.origin, args.destination, args.departure_date, args.return_date))
