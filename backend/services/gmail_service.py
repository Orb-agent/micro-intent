"""
Gmail service module for reading messages and sending emails.
"""
import base64
from email.mime.text import MIMEText
from typing import List, Dict, Any, Optional
from .auth_client import get_service


def list_messages(access_token: str, query: str = "is:unread", max_results: int = 5) -> List[Dict[str, Any]]:
    """Lists messages matching query with metadata header details."""
    service = get_service("gmail", "v1", access_token)
    results = service.users().messages().list(userId="me", q=query, maxResults=max_results).execute()
    messages = results.get("messages", [])
    
    detailed_messages = []
    for msg in messages:
        msg_data = service.users().messages().get(
            userId="me", id=msg["id"], format="metadata",
            metadataHeaders=["Subject", "From", "Date"]
        ).execute()
        headers = {h["name"]: h["value"] for h in msg_data.get("payload", {}).get("headers", [])}
        detailed_messages.append({
            "id": msg["id"],
            "snippet": msg_data.get("snippet", ""),
            "subject": headers.get("Subject", "Sin Asunto"),
            "from": headers.get("From", ""),
            "date": headers.get("Date", "")
        })
    return detailed_messages


def get_message(access_token: str, message_id: str) -> Dict[str, Any]:
    """Retrieves full details of a specific message."""
    service = get_service("gmail", "v1", access_token)
    return service.users().messages().get(userId="me", id=message_id, format="full").execute()


def send_email(access_token: str, to: str, subject: str, body: str) -> Dict[str, Any]:
    """Sends an email via Gmail API using base64url encoded MIME message."""
    service = get_service("gmail", "v1", access_token)
    message = MIMEText(body)
    message["to"] = to
    message["subject"] = subject
    raw_message = base64.urlsafe_b64encode(message.as_bytes()).decode("utf-8")
    return service.users().messages().send(userId="me", body={"raw": raw_message}).execute()
