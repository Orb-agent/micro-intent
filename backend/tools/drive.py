"""Google Drive and Docs tools: find a document and read its text (contracts § Tools).
Read-only, scope drive.readonly. Google Docs, Sheets and Slides are exported as text through
Drive, so the Docs API needs no extra scope. Document content is untrusted data.

Live smoke test, from backend/:
    uv run python -m tools.drive search "packing list"
    uv run python -m tools.drive read <file id>
"""

from __future__ import annotations

import argparse
import re
from typing import Any

import httpx

from tools import google_auth

FILES_URL = "https://www.googleapis.com/drive/v3/files"
MAX_FILES = 5
MAX_TEXT = 4000
EXPORTS = {
    "application/vnd.google-apps.document": "text/plain",
    "application/vnd.google-apps.spreadsheet": "text/csv",
    "application/vnd.google-apps.presentation": "text/plain",
}
FIELDS = "id,name,mimeType,modifiedTime,webViewLink"


def _file(f: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": f["id"],
        "name": f.get("name", ""),
        "type": f.get("mimeType", "").removeprefix("application/vnd.google-apps."),
        "modified": f.get("modifiedTime", ""),
        "link": f.get("webViewLink", ""),
    }


async def drive_search(query: str, client: httpx.AsyncClient | None = None) -> dict[str, Any]:
    """Files whose name or text contains the words, most recently changed first, at most 5."""
    words = query.replace("\\", "\\\\").replace("'", "\\'")
    q = f"(name contains '{words}' or fullText contains '{words}') and trashed = false"
    data = await google_auth.get(FILES_URL, client, q=q, pageSize=MAX_FILES, fields=f"files({FIELDS})")
    files = sorted(data.get("files", []), key=lambda f: f.get("modifiedTime", ""), reverse=True)
    return {"files": [_file(f) for f in files[:MAX_FILES]]}


async def drive_read(file_id: str, client: httpx.AsyncClient | None = None) -> dict[str, Any]:
    """The text of one Doc, Sheet (as CSV), Slides deck or plain-text file, cut to 4000 characters."""
    if not re.fullmatch(r"[\w-]+", file_id or ""):
        raise ValueError("file_id must be an id from drive_search")
    if client is None:
        async with httpx.AsyncClient(timeout=google_auth.TIMEOUT) as http:
            return await drive_read(file_id, http)
    meta = await google_auth.get(f"{FILES_URL}/{file_id}", client, fields=FIELDS)
    mime = meta.get("mimeType", "")
    if mime in EXPORTS:
        r = await google_auth.request("GET", f"{FILES_URL}/{file_id}/export", client, params={"mimeType": EXPORTS[mime]})
    elif mime.startswith("text/") or mime == "application/json":
        r = await google_auth.request("GET", f"{FILES_URL}/{file_id}", client, params={"alt": "media"})
    else:
        return _file(meta) | {"error": f"can't read {mime} files as text"}
    text = r.content.decode("utf-8", errors="replace").lstrip("﻿").strip()
    return _file(meta) | {"text": text[:MAX_TEXT], "truncated": len(text) > MAX_TEXT}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Live smoke test for the Drive and Docs tools")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("search").add_argument("query")
    sub.add_parser("read").add_argument("file_id")
    args = parser.parse_args()
    if args.command == "search":
        google_auth.smoke(lambda: drive_search(args.query))
    else:
        google_auth.smoke(lambda: drive_read(args.file_id))
