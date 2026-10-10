"""Request and response models for the HTTP contract in docs/API.md."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class ElementRef(BaseModel):
    tag: str | None = None
    text: str | None = None
    selector: str | None = None
    attributes: dict[str, str] | None = None


class Selection(BaseModel):
    text: str | None = None
    element: ElementRef | None = None


class Gaze(ElementRef):
    x: float | None = None
    y: float | None = None
    dwell_ms: int | None = None


class PageContext(BaseModel):
    url: str
    title: str
    selection: Selection | None = None
    gaze: Gaze | None = None
    page_text: str | None = None


class IntentRequest(BaseModel):
    intent: str = Field(min_length=1)
    context: PageContext
    locale: Literal["en", "de"] | None = None
    now: str | None = None


class ConfirmRequest(BaseModel):
    action_id: str
    approved: bool = True
    edits: dict[str, Any] | None = None


class A2UIAction(BaseModel):
    name: str
    surfaceId: str
    sourceComponentId: str
    timestamp: str
    context: dict[str, Any] = Field(default_factory=dict)


class A2UIActionMessage(BaseModel):
    """A2UI v0.9.1 client-to-server `action` message."""

    version: Literal["v0.9", "v0.9.1"] = "v0.9.1"
    action: A2UIAction


class Contact(BaseModel):
    id: str
    name: str
    relation: str | None = None
    channel: Literal["sms", "whatsapp", "email"] = "sms"
    address: str | None = None


class Profile(BaseModel):
    name: str = "Batu"
    home: str = "Winterthur"
    transport: Literal["public", "car", "bike", "walk"] = "public"
    contacts: list[Contact] = Field(default_factory=list)
    large_mode: bool = False
    locale: Literal["en", "de"] = "en"


class ProfileUpdate(BaseModel):
    name: str | None = None
    home: str | None = None
    transport: Literal["public", "car", "bike", "walk"] | None = None
    contacts: list[Contact] | None = None
    large_mode: bool | None = None
    locale: Literal["en", "de"] | None = None


class VoiceTokenRequest(BaseModel):
    locale: Literal["en", "de"] | None = None
