"""Google Tasks tool: open tasks across the user's task lists (contracts § Tools).
Read-only, scope tasks.readonly.

Live smoke test, from backend/:
    uv run python -m tools.tasks
"""

from __future__ import annotations

import asyncio
from typing import Any

import httpx

from tools import google_auth

LISTS_URL = "https://tasks.googleapis.com/tasks/v1/users/@me/lists"
TASKS_URL = "https://tasks.googleapis.com/tasks/v1/lists/{list_id}/tasks"
MAX_TASKS = 20


def _task(item: dict[str, Any], list_title: str) -> dict[str, Any]:
    task: dict[str, Any] = {"title": item.get("title", ""), "list": list_title}
    if item.get("due"):
        task["due"] = item["due"][:10]  # Tasks keeps only the date of a due time
    if item.get("notes"):
        task["notes"] = item["notes"][:200]
    return task


async def tasks_list(client: httpx.AsyncClient | None = None) -> dict[str, Any]:
    """Open tasks from every list, due ones first by date, at most 20."""
    if client is None:
        async with httpx.AsyncClient(timeout=google_auth.TIMEOUT) as http:
            return await tasks_list(http)
    lists = (await google_auth.get(LISTS_URL, client, maxResults=20)).get("items", [])
    pages = await asyncio.gather(
        *(
            google_auth.get(TASKS_URL.format(list_id=lst["id"]), client, showCompleted="false", maxResults=MAX_TASKS)
            for lst in lists
        )
    )
    tasks = [
        _task(item, lst.get("title", ""))
        for lst, page in zip(lists, pages)
        for item in page.get("items", [])
        if item.get("title") and item.get("status") != "completed"
    ]
    tasks.sort(key=lambda t: t.get("due") or "9999")
    return {"tasks": tasks[:MAX_TASKS]}


if __name__ == "__main__":
    google_auth.smoke(tasks_list)
