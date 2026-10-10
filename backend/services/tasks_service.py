"""
Google Tasks service module for task management.
"""
from typing import List, Dict, Any, Optional
from .auth_client import get_service


def list_tasks(access_token: str, tasklist: str = "@default") -> List[Dict[str, Any]]:
    """Retrieves uncompleted tasks from specified tasklist."""
    service = get_service("tasks", "v1", access_token)
    results = service.tasks().list(tasklist=tasklist, showCompleted=False).execute()
    return results.get("items", [])


def create_task(
    access_token: str,
    title: str,
    notes: Optional[str] = None,
    due: Optional[str] = None,
    tasklist: str = "@default"
) -> Dict[str, Any]:
    """Creates a new task in the specified tasklist."""
    service = get_service("tasks", "v1", access_token)
    task_body = {"title": title}
    if notes:
        task_body["notes"] = notes
    if due:
        task_body["due"] = due
    return service.tasks().insert(tasklist=tasklist, body=task_body).execute()


def complete_task(access_token: str, task_id: str, tasklist: str = "@default") -> Dict[str, Any]:
    """Marks a task as completed."""
    service = get_service("tasks", "v1", access_token)
    task = service.tasks().get(tasklist=tasklist, task=task_id).execute()
    task["status"] = "completed"
    return service.tasks().update(tasklist=tasklist, task=task_id, body=task).execute()
