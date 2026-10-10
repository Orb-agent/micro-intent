"""Process-local state: profile, pending (unconfirmed) write actions, reminders and the message outbox.

Cloud Run must run a single instance (see deploy.sh) so a /confirm hits the instance that issued the action.
"""

from __future__ import annotations

import json
import logging
import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from .config import settings
from .models import Contact, Profile, ProfileUpdate

log = logging.getLogger(__name__)

ACTION_TTL = timedelta(minutes=30)


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:8]}"


def default_profile() -> Profile:
    return Profile(
        name="Batu",
        home="Winterthur",
        transport="public",
        contacts=[
            Contact(id="mom", name="Mom", relation="mother", channel="sms", address="+41790000000"),
            Contact(id="anna", name="Anna", relation="teammate", channel="email", address="anna@example.com"),
        ],
        large_mode=False,
        locale="en",
    )


@dataclass
class PendingAction:
    id: str
    tool: str
    label: str
    preview: str
    ops: list[dict[str, Any]]
    expires_at: datetime
    status: str = "pending"
    surface_id: str | None = None
    result: dict[str, Any] | None = None


@dataclass
class Store:
    lock: threading.Lock = field(default_factory=threading.Lock)
    profile: Profile = field(default_factory=default_profile)
    actions: dict[str, PendingAction] = field(default_factory=dict)
    reminders: list[dict[str, Any]] = field(default_factory=list)
    outbox: list[dict[str, Any]] = field(default_factory=list)

    def load_profile(self) -> None:
        if settings.profile_path and Path(settings.profile_path).exists():
            try:
                self.profile = Profile.model_validate_json(Path(settings.profile_path).read_text())
            except Exception as exc:
                log.warning("could not load profile from %s: %s", settings.profile_path, exc)

    def update_profile(self, upd: ProfileUpdate) -> Profile:
        with self.lock:
            merged = self.profile.model_dump() | upd.model_dump(exclude_unset=True, exclude_none=True)
            self.profile = Profile.model_validate(merged)
            if settings.profile_path:
                try:
                    Path(settings.profile_path).write_text(json.dumps(self.profile.model_dump(), indent=2))
                except OSError as exc:
                    log.warning("could not persist profile: %s", exc)
            return self.profile

    def add_action(self, tool: str, label: str, preview: str, ops: list[dict[str, Any]]) -> PendingAction:
        act = PendingAction(
            id=new_id("act"), tool=tool, label=label, preview=preview, ops=ops, expires_at=datetime.now(settings.tz) + ACTION_TTL
        )
        with self.lock:
            self.actions[act.id] = act
        return act

    def get_action(self, action_id: str) -> PendingAction | None:
        with self.lock:
            act = self.actions.get(action_id)
        if act and act.status == "pending" and act.expires_at < datetime.now(settings.tz):
            return None
        return act

    def reset(self) -> None:
        with self.lock:
            self.actions.clear()
            self.reminders.clear()
            self.outbox.clear()


store = Store()
store.load_profile()
