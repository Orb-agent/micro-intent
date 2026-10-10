"""Shared fixtures: a fake Google for the Workspace tools, no live calls."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import httpx
import pytest

from tools import google_auth

GOOGLE_FIXTURES = Path(__file__).parent.parent / "fixtures" / "google"


def google_fixture(name: str) -> Any:
    return json.loads((GOOGLE_FIXTURES / name).read_text())


class FakeGoogle:
    """Answers the OAuth token call, then each routed URL path with its JSON (or bytes);
    records every request."""

    def __init__(self) -> None:
        self.routes: dict[str, Any] = {}
        self.requests: list[httpx.Request] = []

    def route(self, path: str, body: Any, status: int = 200) -> None:
        self.routes[path] = (body, status)

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if str(request.url) == google_auth.TOKEN_URL:
            return httpx.Response(200, json={"access_token": "test-access", "expires_in": 3599})
        assert request.headers["Authorization"] == "Bearer test-access"
        body, status = self.routes[request.url.path]
        if isinstance(body, bytes):
            return httpx.Response(status, content=body)
        return httpx.Response(status, json=body)

    def client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(transport=httpx.MockTransport(self.handler))

    def api_requests(self) -> list[httpx.Request]:
        return [r for r in self.requests if str(r.url) != google_auth.TOKEN_URL]


@pytest.fixture
def fake_google(monkeypatch) -> FakeGoogle:
    for name in google_auth.OAUTH_VARS:
        monkeypatch.setenv(name, f"test-{name.lower()}")
    google_auth.clear_token()
    yield FakeGoogle()
    google_auth.clear_token()


@pytest.fixture
def no_google(monkeypatch) -> None:
    for name in (*google_auth.OAUTH_VARS, "SERPAPI_API_KEY", "GOOGLE_MAPS_API_KEY"):
        monkeypatch.delenv(name, raising=False)
    google_auth.clear_token()
