"""Drive and Docs tools on hand-made responses in the documented API shape; no live calls."""

from __future__ import annotations

import pytest
from conftest import GOOGLE_FIXTURES, google_fixture

from tools import google_auth
from tools.drive import drive_read, drive_search


async def test_search(fake_google):
    fake_google.route("/drive/v3/files", google_fixture("drive_files.json"))
    async with fake_google.client() as client:
        result = await drive_search("Anna's packing list", client=client)

    params = fake_google.api_requests()[0].url.params
    assert params["q"] == (
        "(name contains 'Anna\\'s packing list' or fullText contains 'Anna\\'s packing list') and trashed = false"
    )
    assert [f["name"] for f in result["files"]] == ["Packing list Lisbon", "Packing list 2025"]  # newest first
    assert result["files"][0] == {
        "id": "1AbC-new",
        "name": "Packing list Lisbon",
        "type": "document",
        "modified": "2026-10-08T19:02:00.000Z",
        "link": "https://docs.google.com/document/d/1AbC-new/edit",
    }


async def test_read_google_doc(fake_google):
    fake_google.route("/drive/v3/files/1AbC-new", google_fixture("drive_meta.json"))
    fake_google.route("/drive/v3/files/1AbC-new/export", (GOOGLE_FIXTURES / "drive_export.txt").read_bytes())
    async with fake_google.client() as client:
        result = await drive_read("1AbC-new", client=client)

    assert fake_google.api_requests()[1].url.params["mimeType"] == "text/plain"
    assert result["text"] == "Packing list Lisbon\n- Passport\n- Charger"  # the fixture has LF since 443e5df
    assert result["truncated"] is False and result["type"] == "document"


async def test_read_binary_file_is_an_error(fake_google):
    fake_google.route("/drive/v3/files/img1", {"id": "img1", "name": "photo.jpg", "mimeType": "image/jpeg"})
    async with fake_google.client() as client:
        result = await drive_read("img1", client=client)
    assert result["error"] == "can't read image/jpeg files as text"


async def test_not_configured(no_google):
    with pytest.raises(google_auth.NotConfigured):
        await drive_search("packing")
