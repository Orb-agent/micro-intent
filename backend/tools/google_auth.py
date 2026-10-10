"""Google Workspace REST access with the temporary account's refresh token (contracts § Tools).

Every Workspace tool goes through `get`: it swaps the refresh token for an access token, caches
that token until shortly before it expires, and raises `NotConfigured` when the credentials are
missing, so a tool reports "not configured" instead of crashing.
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Awaitable, Callable

import httpx

TOKEN_URL = "https://oauth2.googleapis.com/token"
OAUTH_VARS = ("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "GOOGLE_REFRESH_TOKEN")
TIMEOUT = 8.0

_token: tuple[str, float] | None = None  # access token and its monotonic expiry
_scopes: set[str] | None = None  # what the refresh token grants, from the last token response


class NotConfigured(RuntimeError):
    """A credential the tool needs is not set."""


def oauth_configured() -> bool:
    return all(os.environ.get(name) for name in OAUTH_VARS)


def require_oauth() -> None:
    if not oauth_configured():
        missing = ", ".join(name for name in OAUTH_VARS if not os.environ.get(name))
        raise NotConfigured(f"Google account not configured: set {missing}")


async def access_token(client: httpx.AsyncClient) -> str:
    global _token, _scopes
    require_oauth()
    if _token and time.monotonic() < _token[1]:
        return _token[0]
    r = await client.post(
        TOKEN_URL,
        data={
            "client_id": os.environ["GOOGLE_CLIENT_ID"],
            "client_secret": os.environ["GOOGLE_CLIENT_SECRET"],
            "refresh_token": os.environ["GOOGLE_REFRESH_TOKEN"],
            "grant_type": "refresh_token",
        },
    )
    r.raise_for_status()
    data = r.json()
    if "scope" in data:
        _scopes = set(data["scope"].split())
    _token = (data["access_token"], time.monotonic() + int(data.get("expires_in", 3600)) - 60)
    return _token[0]


def clear_token() -> None:
    global _token, _scopes
    _token = _scopes = None


async def granted_scopes() -> set[str] | None:
    """The scopes the refresh token grants, or None if unknown (not configured, or Google failed)."""
    if not oauth_configured():
        return None
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as http:
            await access_token(http)
    except httpx.HTTPError:
        return None
    return _scopes


async def request(
    method: str,
    url: str,
    client: httpx.AsyncClient | None = None,
    *,
    params: dict[str, Any] | None = None,
    json: dict[str, Any] | None = None,
) -> httpx.Response:
    """One authorized Workspace call; raises for HTTP errors."""
    require_oauth()
    if client is None:
        async with httpx.AsyncClient(timeout=TIMEOUT) as http:
            return await request(method, url, http, params=params, json=json)
    headers = {"Authorization": f"Bearer {await access_token(client)}"}
    r = await client.request(method, url, params=params, json=json, headers=headers)
    r.raise_for_status()
    return r


async def get(url: str, client: httpx.AsyncClient | None = None, **params: Any) -> dict[str, Any]:
    return (await request("GET", url, client, params=params or None)).json()


def smoke(coro_fn: Callable[[], Awaitable[Any]]) -> None:
    """Run a tool's live smoke test from the CLI: print the JSON result, or one clean line and
    exit 2 when a credential is missing, or exit 1 on an API error. Never a traceback."""
    from dotenv import load_dotenv

    backend = Path(__file__).parent.parent  # the same .env files agent.py loads
    load_dotenv(backend / ".env")
    load_dotenv(backend.parent / ".env")
    try:
        result = asyncio.run(coro_fn())
    except NotConfigured as e:
        print(f"not configured: {e}", file=sys.stderr)
        raise SystemExit(2)
    except httpx.HTTPStatusError as e:
        print(f"failed: HTTP {e.response.status_code} from {e.request.url.host}: {e.response.text[:300]}", file=sys.stderr)
        raise SystemExit(1)
    except (httpx.HTTPError, ValueError) as e:
        print(f"failed: {type(e).__name__}: {e}", file=sys.stderr)
        raise SystemExit(1)
    print(json.dumps(result, indent=2, ensure_ascii=False))
