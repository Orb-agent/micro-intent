"""A2UI v0.9.1 messages for the Micro Intent catalog (see docs/API.md)."""

from __future__ import annotations

from typing import Any

VERSION = "v0.9.1"
CATALOG_ID = "https://micro-intent.app/a2ui/catalog/v1"
COMPONENTS = ("EventCard", "ConflictCard", "TrainCard", "ReminderCard", "MessageDraftCard", "ConfirmCard")


def event_action(name: str, **context: Any) -> dict[str, Any]:
    return {"event": {"name": name, "context": context}}


def open_url_action(url: str) -> dict[str, Any]:
    return {"functionCall": {"call": "openUrl", "args": {"url": url}}}


def surface(surface_id: str, component: str, props: dict[str, Any], data: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    """One card: createSurface + updateComponents (+ updateDataModel) with a single root component."""
    msgs: list[dict[str, Any]] = [
        {"version": VERSION, "createSurface": {"surfaceId": surface_id, "catalogId": CATALOG_ID}},
        {
            "version": VERSION,
            "updateComponents": {"surfaceId": surface_id, "components": [{"id": "root", "component": component, **props}]},
        },
    ]
    if data is not None:
        msgs.append({"version": VERSION, "updateDataModel": {"surfaceId": surface_id, "path": "/", "value": data}})
    return msgs


def delete_surface(surface_id: str) -> dict[str, Any]:
    return {"version": VERSION, "deleteSurface": {"surfaceId": surface_id}}
