"""
Google Calendar service module for event retrieval and creation.
"""
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional
from .auth_client import get_service


def list_events(access_token: str, max_results: int = 10, time_min: Optional[str] = None) -> List[Dict[str, Any]]:
    """Lists upcoming events from user's primary calendar."""
    service = get_service("calendar", "v3", access_token)
    if not time_min:
        time_min = datetime.now(timezone.utc).isoformat()
    
    events_result = service.events().list(
        calendarId="primary",
        timeMin=time_min,
        maxResults=max_results,
        singleEvents=True,
        orderBy="startTime"
    ).execute()
    return events_result.get("items", [])


def create_event(
    access_token: str,
    summary: str,
    start_time: str,
    end_time: str,
    description: Optional[str] = None,
    attendees: Optional[List[str]] = None
) -> Dict[str, Any]:
    """Creates a new event in the user's primary calendar."""
    service = get_service("calendar", "v3", access_token)
    event_body = {
        "summary": summary,
        "description": description or "",
        "start": {"dateTime": start_time},
        "end": {"dateTime": end_time},
    }
    if attendees:
        event_body["attendees"] = [{"email": email} for email in attendees]

    return service.events().insert(calendarId="primary", body=event_body).execute()


def delete_event(access_token: str, event_id: str) -> Dict[str, Any]:
    """Deletes an event by its ID."""
    service = get_service("calendar", "v3", access_token)
    return service.events().delete(calendarId="primary", eventId=event_id).execute()
