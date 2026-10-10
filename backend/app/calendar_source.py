"""Calendar sources behind one interface: a seeded mock and the Google Calendar API.

The mock plants the demo conflict: a daily "Team sync 18:00-18:30" on the user's work calendar.
"""

from __future__ import annotations

import logging
import threading
import uuid
from dataclasses import asdict, dataclass
from datetime import date, datetime, time, timedelta
from typing import Protocol

from .config import settings

log = logging.getLogger(__name__)

ME = "me"


@dataclass
class CalEvent:
    id: str
    title: str
    start: datetime
    end: datetime
    calendar: str = "Work"
    owner: str = ME
    location: str | None = None

    def to_json(self) -> dict:
        d = asdict(self)
        d["start"] = self.start.isoformat()
        d["end"] = self.end.isoformat()
        return {k: v for k, v in d.items() if v is not None}


class CalendarSource(Protocol):
    name: str

    def list_events(self, start: datetime, end: datetime, owner: str = ME) -> list[CalEvent]: ...

    def get_event(self, event_id: str) -> CalEvent | None: ...

    def create_event(
        self, title: str, start: datetime, end: datetime, location: str | None = None, description: str | None = None
    ) -> CalEvent: ...

    def move_event(self, event_id: str, start: datetime, end: datetime) -> CalEvent: ...


def overlaps(a_start: datetime, a_end: datetime, b_start: datetime, b_end: datetime) -> bool:
    return a_start < b_end and b_start < a_end


# Daily seeded events per owner: (title, start, end, calendar label).
_DAILY_SEED: dict[str, list[tuple[str, time, time, str]]] = {
    ME: [("Team sync", time(18, 0), time(18, 30), "Work")],
    "anna": [("Client workshop", time(13, 0), time(16, 30), "Anna")],
    "mom": [("Choir rehearsal", time(19, 0), time(20, 30), "Mom")],
}


class MockCalendar:
    """In-memory calendar; days are seeded lazily so any queried date carries the planted conflict."""

    name = "mock"

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.reset()

    def reset(self) -> None:
        with self._lock:
            self._events: dict[str, CalEvent] = {}
            self._seeded: set[date] = set()

    def _seed_day(self, day: date) -> None:
        if day in self._seeded:
            return
        self._seeded.add(day)
        for owner, items in _DAILY_SEED.items():
            for title, t0, t1, cal in items:
                slug = title.lower().replace(" ", "_")
                eid = f"evt_{slug}_{day:%Y%m%d}" if owner == ME else f"evt_{owner}_{slug}_{day:%Y%m%d}"
                self._events[eid] = CalEvent(
                    id=eid,
                    title=title,
                    start=datetime.combine(day, t0, settings.tz),
                    end=datetime.combine(day, t1, settings.tz),
                    calendar=cal,
                    owner=owner,
                )

    def _seed_range(self, start: datetime, end: datetime) -> None:
        day = start.astimezone(settings.tz).date()
        last = end.astimezone(settings.tz).date()
        while day <= last:
            self._seed_day(day)
            day += timedelta(days=1)

    def list_events(self, start: datetime, end: datetime, owner: str = ME) -> list[CalEvent]:
        with self._lock:
            self._seed_range(start, end)
            found = [e for e in self._events.values() if e.owner == owner and overlaps(e.start, e.end, start, end)]
        return sorted(found, key=lambda e: e.start)

    def get_event(self, event_id: str) -> CalEvent | None:
        with self._lock:
            ev = self._events.get(event_id)
            if ev is None and event_id.startswith("evt_") and event_id[-8:].isdigit():
                # Seed the day an id refers to so ids from earlier cards stay valid.
                self._seed_day(datetime.strptime(event_id[-8:], "%Y%m%d").date())
                ev = self._events.get(event_id)
            return ev

    def create_event(
        self, title: str, start: datetime, end: datetime, location: str | None = None, description: str | None = None
    ) -> CalEvent:
        ev = CalEvent(id=f"evt_{uuid.uuid4().hex[:8]}", title=title, start=start, end=end, calendar="Personal", location=location)
        with self._lock:
            self._seed_range(start, end)
            self._events[ev.id] = ev
        return ev

    def move_event(self, event_id: str, start: datetime, end: datetime) -> CalEvent:
        ev = self.get_event(event_id)
        if ev is None:
            raise KeyError(f"unknown event {event_id}")
        with self._lock:
            ev.start, ev.end = start, end
        return ev


class GoogleCalendar:
    """Google Calendar API for the user's own calendar; other people's calendars stay on the mock."""

    name = "google"

    def __init__(self, token_file: str | None, calendar_id: str, mock: MockCalendar) -> None:
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build

        scopes = ["https://www.googleapis.com/auth/calendar"]
        if token_file:
            creds = Credentials.from_authorized_user_file(token_file, scopes)
        else:
            import google.auth

            creds, _ = google.auth.default(scopes=scopes)
        self._svc = build("calendar", "v3", credentials=creds, cache_discovery=False)
        self._cal_id = calendar_id
        self._mock = mock

    def _to_event(self, item: dict) -> CalEvent:
        def parse(v: dict) -> datetime:
            if "dateTime" in v:
                return datetime.fromisoformat(v["dateTime"]).astimezone(settings.tz)
            return datetime.combine(date.fromisoformat(v["date"]), time(0), settings.tz)

        return CalEvent(
            id=item["id"],
            title=item.get("summary", "(busy)"),
            start=parse(item["start"]),
            end=parse(item["end"]),
            calendar="Google",
            location=item.get("location"),
        )

    def list_events(self, start: datetime, end: datetime, owner: str = ME) -> list[CalEvent]:
        if owner != ME:
            return self._mock.list_events(start, end, owner)
        res = (
            self._svc.events()
            .list(calendarId=self._cal_id, timeMin=start.isoformat(), timeMax=end.isoformat(), singleEvents=True, orderBy="startTime")
            .execute()
        )
        return [self._to_event(i) for i in res.get("items", []) if i.get("transparency") != "transparent"]

    def get_event(self, event_id: str) -> CalEvent | None:
        try:
            return self._to_event(self._svc.events().get(calendarId=self._cal_id, eventId=event_id).execute())
        except Exception:
            return None

    def create_event(
        self, title: str, start: datetime, end: datetime, location: str | None = None, description: str | None = None
    ) -> CalEvent:
        body = {"summary": title, "start": {"dateTime": start.isoformat()}, "end": {"dateTime": end.isoformat()}}
        if location:
            body["location"] = location
        if description:
            body["description"] = description
        return self._to_event(self._svc.events().insert(calendarId=self._cal_id, body=body).execute())

    def move_event(self, event_id: str, start: datetime, end: datetime) -> CalEvent:
        body = {"start": {"dateTime": start.isoformat()}, "end": {"dateTime": end.isoformat()}}
        return self._to_event(self._svc.events().patch(calendarId=self._cal_id, eventId=event_id, body=body).execute())


mock_calendar = MockCalendar()
_calendar: CalendarSource | None = None


def get_calendar() -> CalendarSource:
    global _calendar
    if _calendar is None:
        _calendar = mock_calendar
        if settings.calendar_source == "google":
            try:
                _calendar = GoogleCalendar(settings.google_calendar_token_file, settings.google_calendar_id, mock_calendar)
            except Exception as exc:  # missing credentials must not break the demo
                log.warning("Google Calendar unavailable, using mock: %s", exc)
    return _calendar


def busy_and_conflicts(start: datetime, end: datetime, owner: str = ME) -> list[CalEvent]:
    """Events of `owner` overlapping [start, end); reads fall back to the mock if the live source fails."""
    cal = get_calendar()
    try:
        return cal.list_events(start, end, owner)
    except Exception as exc:
        log.warning("calendar read failed on %s, using mock: %s", cal.name, exc)
        return mock_calendar.list_events(start, end, owner)


def free_slots(
    owners: list[str], day_start: datetime, day_end: datetime, duration: timedelta, step: timedelta = timedelta(minutes=30)
) -> list[tuple[datetime, datetime]]:
    """Free windows of at least `duration` shared by all owners, aligned to `step`."""
    busy = [e for o in owners for e in busy_and_conflicts(day_start, day_end, o)]
    slots: list[tuple[datetime, datetime]] = []
    t = day_start
    while t + duration <= day_end:
        if not any(overlaps(t, t + duration, b.start, b.end) for b in busy):
            slots.append((t, t + duration))
        t += step
    return slots
