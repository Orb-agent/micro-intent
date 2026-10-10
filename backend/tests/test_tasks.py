"""Tasks tool on hand-made responses in the documented API shape; no live calls."""

from __future__ import annotations

import pytest
from conftest import google_fixture

from tools import google_auth
from tools.tasks import tasks_list


async def test_open_tasks_across_lists(fake_google):
    fake_google.route("/tasks/v1/users/@me/lists", google_fixture("tasks_lists.json"))
    fake_google.route("/tasks/v1/lists/L1/tasks", google_fixture("tasks_L1.json"))
    fake_google.route("/tasks/v1/lists/L2/tasks", google_fixture("tasks_L2.json"))
    async with fake_google.client() as client:
        result = await tasks_list(client=client)

    assert all(r.url.params["showCompleted"] == "false" for r in fake_google.api_requests()[1:])
    assert result == {
        "tasks": [
            {"title": "Send slides to Acme", "list": "My Tasks", "due": "2026-10-16"},
            {"title": "Check in for LX 1820", "list": "Trip", "due": "2026-10-19"},
            {"title": "Call the bank", "list": "My Tasks", "notes": "about the card"},
        ]
    }


async def test_not_configured(no_google):
    with pytest.raises(google_auth.NotConfigured):
        await tasks_list()
