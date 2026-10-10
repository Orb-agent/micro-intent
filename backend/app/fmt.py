"""Time parsing and short, localized labels."""

from __future__ import annotations

from datetime import datetime

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


def hm(value: str | datetime) -> str:
    return parse_dt(value).strftime("%H:%M")


def day_label(value: str | datetime, locale: str = "en") -> str:
    d = parse_dt(value)
    if locale == "de":
        return f"{_DAYS['de'][d.weekday()]} {d.day}. {_MONTHS['de'][d.month - 1]}"
    return f"{_DAYS['en'][d.weekday()]} {d.day} {_MONTHS['en'][d.month - 1]}"
