"""Gmail tools: search messages and read one, e.g. a flight booking (contracts § Tools).
Read-only, scope gmail.readonly. Mail content is untrusted data.

Live smoke test, from backend/:
    uv run python -m tools.gmail search "flight OR booking"
    uv run python -m tools.gmail read <message id>
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import html
import re
from typing import Any

import httpx

from tools import google_auth

MESSAGES_URL = "https://gmail.googleapis.com/gmail/v1/users/me/messages"
MAX_RESULTS = 5
MAX_BODY = 4000


def _decode(data: str) -> str:
    return base64.urlsafe_b64decode(data + "=" * (-len(data) % 4)).decode("utf-8", errors="replace")


def _find(payload: dict[str, Any], mime: str) -> str:
    if payload.get("mimeType") == mime and payload.get("body", {}).get("data"):
        return _decode(payload["body"]["data"])
    return next((text for part in payload.get("parts", []) if (text := _find(part, mime))), "")


def _strip_html(markup: str) -> str:
    markup = re.sub(r"(?is)<(script|style|head)\b.*?</\1>", " ", markup)
    markup = re.sub(r"(?i)<br\s*/?>|</(p|div|tr|li|h\d)>", "\n", markup)
    text = html.unescape(re.sub(r"<[^>]+>", " ", markup))
    lines = (re.sub(r"\s+", " ", line).strip() for line in text.splitlines())
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()


def extract_body(payload: dict[str, Any]) -> str:
    """The plain-text body of a Gmail `format=full` payload; HTML-only mail is reduced to text."""
    if text := _find(payload, "text/plain"):
        return text.strip()
    if markup := _find(payload, "text/html"):
        return _strip_html(markup)
    data = payload.get("body", {}).get("data")
    return _decode(data).strip() if data else ""


def _headers(message: dict[str, Any]) -> dict[str, str]:
    return {h.get("name", "").lower(): h.get("value", "") for h in message.get("payload", {}).get("headers", [])}


def _summary(message: dict[str, Any]) -> dict[str, Any]:
    h = _headers(message)
    return {
        "id": message["id"],
        "subject": h.get("subject", ""),
        "from": h.get("from", ""),
        "date": h.get("date", ""),
        "snippet": html.unescape(message.get("snippet", "")),
    }


async def gmail_search(query: str, client: httpx.AsyncClient | None = None) -> dict[str, Any]:
    """Messages matching a Gmail search query (same syntax as the Gmail search box), newest first, at most 5."""
    if client is None:
        async with httpx.AsyncClient(timeout=google_auth.TIMEOUT) as http:
            return await gmail_search(query, http)
    listing = await google_auth.get(MESSAGES_URL, client, q=query, maxResults=MAX_RESULTS)
    ids = [m["id"] for m in listing.get("messages", [])[:MAX_RESULTS]]
    messages = await asyncio.gather(
        *(
            google_auth.get(f"{MESSAGES_URL}/{i}", client, format="metadata", metadataHeaders=["Subject", "From", "Date"])
            for i in ids
        )
    )
    return {"messages": [_summary(m) for m in messages]}


async def gmail_read(message_id: str, client: httpx.AsyncClient | None = None) -> dict[str, Any]:
    """One message with its text body, cut to 4000 characters."""
    if not re.fullmatch(r"[0-9a-zA-Z]+", message_id or ""):
        raise ValueError("message_id must be an id from gmail_search")
    message = await google_auth.get(f"{MESSAGES_URL}/{message_id}", client, format="full")
    summary = _summary(message)
    del summary["snippet"]
    return summary | {"body": extract_body(message.get("payload", {}))[:MAX_BODY]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Live smoke test for the Gmail tools")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("search").add_argument("query", nargs="?", default="flight OR booking")
    sub.add_parser("read").add_argument("message_id")
    args = parser.parse_args()
    if args.command == "search":
        google_auth.smoke(lambda: gmail_search(args.query))
    else:
        google_auth.smoke(lambda: gmail_read(args.message_id))
