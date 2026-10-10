"""
Google Docs service module for document creation and text manipulation.
"""
from typing import Dict, Any, Optional
from .auth_client import get_service


def create_document(access_token: str, title: str, content: Optional[str] = None) -> Dict[str, Any]:
    """Creates a new Google Document, optionally inserting initial content."""
    docs_service = get_service("docs", "v1", access_token)
    doc = docs_service.documents().create(body={"title": title}).execute()
    doc_id = doc.get("documentId")

    if content and doc_id:
        requests = [{
            "insertText": {
                "location": {"index": 1},
                "text": content
            }
        }]
        docs_service.documents().batchUpdate(documentId=doc_id, body={"requests": requests}).execute()

    return doc


def get_document(access_token: str, document_id: str) -> Dict[str, Any]:
    """Retrieves document metadata and body."""
    docs_service = get_service("docs", "v1", access_token)
    return docs_service.documents().get(documentId=document_id).execute()


def append_text(access_token: str, document_id: str, text: str) -> Dict[str, Any]:
    """Appends text at the end of the specified Google Document."""
    docs_service = get_service("docs", "v1", access_token)
    doc = docs_service.documents().get(documentId=document_id).execute()
    body_content = doc.get("body", {}).get("content", [])
    end_index = 1
    if body_content:
        end_index = body_content[-1].get("endIndex", 1) - 1

    requests = [{
        "insertText": {
            "location": {"index": max(1, end_index)},
            "text": text
        }
    }]
    return docs_service.documents().batchUpdate(documentId=document_id, body={"requests": requests}).execute()
