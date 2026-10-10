"""
Google Drive service module for searching and creating files.
"""
from typing import List, Dict, Any, Optional
from googleapiclient.http import MediaInMemoryUpload
from .auth_client import get_service


def search_files(access_token: str, query: Optional[str] = None, page_size: int = 10) -> List[Dict[str, Any]]:
    """Searches files in user's Drive."""
    service = get_service("drive", "v3", access_token)
    q = query or "trashed = false"
    results = service.files().list(
        q=q,
        pageSize=page_size,
        fields="files(id, name, mimeType, webViewLink, modifiedTime)"
    ).execute()
    return results.get("files", [])


def create_file(access_token: str, name: str, content: str, mime_type: str = "text/plain") -> Dict[str, Any]:
    """Creates a file with text content in user's Google Drive."""
    service = get_service("drive", "v3", access_token)
    file_metadata = {"name": name}
    media = MediaInMemoryUpload(content.encode("utf-8"), mimetype=mime_type, resumable=True)
    return service.files().create(body=file_metadata, media_body=media, fields="id, name, webViewLink").execute()
