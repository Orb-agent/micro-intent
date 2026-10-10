"""Gmail tools on hand-made responses in the documented API shape; no live calls."""

from __future__ import annotations

import pytest
from conftest import google_fixture

from tools import google_auth
from tools.gmail import gmail_read, gmail_search


async def test_search(fake_google):
    fake_google.route("/gmail/v1/users/me/messages", google_fixture("gmail_list.json"))
    fake_google.route("/gmail/v1/users/me/messages/18f2a1", google_fixture("gmail_meta_1.json"))
    fake_google.route("/gmail/v1/users/me/messages/18f2a2", google_fixture("gmail_meta_2.json"))
    async with fake_google.client() as client:
        result = await gmail_search("flight OR booking", client=client)

    listing, *gets = fake_google.api_requests()
    assert listing.url.params["q"] == "flight OR booking" and listing.url.params["maxResults"] == "5"
    assert all(r.url.params["format"] == "metadata" for r in gets)
    assert [sum(1 for r in fake_google.requests if "oauth2" in str(r.url))] == [1]  # one token for all calls
    assert result["messages"][0] == {
        "id": "18f2a1",
        "subject": "Your booking K7Q2ZP: Zürich – Lisbon",
        "from": "SWISS <noreply@swiss.com>",
        "date": "Fri, 9 Oct 2026 10:12:00 +0200",
        "snippet": "LX 1820 Zürich & Lisbon, Tue 20 Oct 07:10",
    }
    assert [m["id"] for m in result["messages"]] == ["18f2a1", "18f2a2"]


async def test_read_html_only_mail(fake_google):
    fake_google.route("/gmail/v1/users/me/messages/18f2a1", google_fixture("gmail_full_html.json"))
    async with fake_google.client() as client:
        result = await gmail_read("18f2a1", client=client)

    assert fake_google.api_requests()[0].url.params["format"] == "full"
    assert result["subject"] == "Your booking K7Q2ZP: Zürich – Lisbon"
    assert result["body"] == "Booking K7Q2ZP\nFlight LX 1820 & seat 14A\nZürich ZRH 07:10 → Lisbon LIS 09:15\nTue 20 Oct 2026"


async def test_read_rejects_odd_ids(fake_google):
    async with fake_google.client() as client:
        with pytest.raises(ValueError):
            await gmail_read("../../drafts", client=client)
    assert fake_google.requests == []


async def test_not_configured(no_google):
    with pytest.raises(google_auth.NotConfigured):
        await gmail_search("flight")
