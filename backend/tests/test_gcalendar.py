"""Calendar tools on hand-made responses in the documented API shape; no live calls."""

from __future__ import annotations

import json
from datetime import datetime

import pytest
from conftest import google_fixture

from tools import google_auth
from tools.gcalendar import TZ, calendar_events, calendar_free_slots, free_slots


async def test_events(fake_google):
    fake_google.route("/calendar/v3/calendars/primary/events", google_fixture("calendar_events.json"))
    async with fake_google.client() as client:
        result = await calendar_events("2026-10-15", "2026-10-20T00:00:00+02:00", query="call", client=client)

    params = fake_google.api_requests()[0].url.params
    assert params["timeMin"] == "2026-10-15T00:00:00+02:00"  # a bare date is Zurich midnight
    assert params["timeMax"] == "2026-10-20T00:00:00+02:00"
    assert params["singleEvents"] == "true" and params["orderBy"] == "startTime" and params["q"] == "call"
    assert result == {
        "events": [
            {"title": "Call with Acme", "source": "calendar", "start": "2026-10-15T17:30:00+02:00",
             "end": "2026-10-15T17:45:00+02:00", "location": "Zoom"},
            {"title": "Hackathon", "source": "luma", "start": "2026-10-17T00:00:00+02:00",
             "end": "2026-10-19T00:00:00+02:00", "all_day": True, "location": "Zürich"},
        ]
    }


async def test_shared_free_slots(fake_google):
    fake_google.route("/calendar/v3/freeBusy", google_fixture("calendar_freebusy.json"))
    async with fake_google.client() as client:
        result = await calendar_free_slots(
            "2026-10-15T08:00:00+02:00", "2026-10-15T20:00:00+02:00", 60,
            ["anna@example.com", "nobody@example.com"], client=client,
        )

    body = json.loads(fake_google.api_requests()[0].content)
    assert body["items"] == [{"id": "primary"}, {"id": "anna@example.com"}, {"id": "nobody@example.com"}]
    # Busy (local): me 09-11 and 17:30-17:45, Anna 10:30-13:00 and 14:00-14:20.
    assert result == {
        "slots": [
            {"start": "2026-10-15T08:00:00+02:00", "end": "2026-10-15T09:00:00+02:00"},
            {"start": "2026-10-15T13:00:00+02:00", "end": "2026-10-15T14:00:00+02:00"},
            {"start": "2026-10-15T14:20:00+02:00", "end": "2026-10-15T17:30:00+02:00"},
            {"start": "2026-10-15T17:45:00+02:00", "end": "2026-10-15T20:00:00+02:00"},
        ],
        "unavailable": ["nobody@example.com"],
    }


def test_free_slots_span_days_inside_day_hours():
    t = lambda s: datetime.fromisoformat(s).replace(tzinfo=TZ)  # noqa: E731
    busy = [(t("2026-10-15T07:00"), t("2026-10-15T19:30"))]
    slots = free_slots(busy, t("2026-10-15T00:00"), t("2026-10-17T00:00"), 30)
    assert slots == [
        {"start": "2026-10-15T19:30:00+02:00", "end": "2026-10-15T20:00:00+02:00"},
        {"start": "2026-10-16T08:00:00+02:00", "end": "2026-10-16T20:00:00+02:00"},
    ]


async def test_not_configured(no_google):
    with pytest.raises(google_auth.NotConfigured):
        await calendar_events("2026-10-15", "2026-10-16")
