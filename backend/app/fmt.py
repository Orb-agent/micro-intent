"""Time parsing and short, localized labels."""

from __future__ import annotations

from datetime import datetime, timedelta

from .config import settings

_DAYS = {"en": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], "de": ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]}
_MONTHS = {
    "en": ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
    "de": ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"],
}


def parse_dt(value: str | datetime) -> datetime:
    dt = value if isinstance(value, datetime) else datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=settings.tz)
    return dt.astimezone(settings.tz)


def ceil_quarter(dt: datetime) -> datetime:
    """Round up to the next quarter hour (17:19 -> 17:30, 17:15 -> 17:15)."""
    dt = dt.replace(second=0, microsecond=0)
    return dt + timedelta(minutes=(-dt.minute) % 15)


def round_quarter(dt: datetime) -> datetime:
    """Round to the nearest quarter hour (17:19 -> 17:15, 17:23 -> 17:30)."""
    dt = dt.replace(second=0, microsecond=0)
    down = dt - timedelta(minutes=dt.minute % 15)
    return down + timedelta(minutes=15) if dt.minute % 15 >= 8 else down


def hm(value: str | datetime) -> str:
    return parse_dt(value).strftime("%H:%M")


def day_label(value: str | datetime, locale: str = "en") -> str:
    d = parse_dt(value)
    if locale == "de":
        return f"{_DAYS['de'][d.weekday()]} {d.day}. {_MONTHS['de'][d.month - 1]}"
    return f"{_DAYS['en'][d.weekday()]} {d.day} {_MONTHS['en'][d.month - 1]}"
