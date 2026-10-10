"""
Automated unit & integration tests for the Lumi Backend.
"""
import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient

from main import app
from services.auth_client import get_credentials
from agent_engine import build_workspace_tool

client = TestClient(app)


def test_health_endpoint():
    """Checks that /health responds 200 OK."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["service"] == "Lumi Backend"
    assert "gemini_configured" in data


def test_plan_missing_authorization():
    """Checks that /api/plan rejects requests missing the Authorization header."""
    response = client.post("/api/plan", json={"prompt": "Revisa mis correos"})
    assert response.status_code == 401
    assert "Authorization header is required" in response.json()["detail"]


def test_plan_invalid_token_format():
    """Checks that /api/plan rejects malformed Authorization headers."""
    response = client.post(
        "/api/plan",
        json={"prompt": "Revisa mis correos"},
        headers={"Authorization": "Basic 12345"}
    )
    assert response.status_code == 401
    assert "Invalid authorization format" in response.json()["detail"]


def test_plan_empty_prompt():
    """Checks that /api/plan rejects empty prompts."""
    response = client.post(
        "/api/plan",
        json={"prompt": "   "},
        headers={"Authorization": "Bearer mock_token_123"}
    )
    assert response.status_code == 400
    assert "Prompt cannot be empty" in response.json()["detail"]


@patch("main.agent.run")
def test_plan_successful_execution(mock_agent_run):
    """Mocks agent execution and verifies /api/plan response structure."""
    mock_agent_run.return_value = {
        "reply": "Tienes 2 reuniones agendadas hoy.",
        "actions": [
            {
                "tool": "calendar_list_events",
                "arguments": {"max_results": 5},
                "status": "success",
                "result": [{"summary": "Daily Standup"}]
            }
        ]
    }

    response = client.post(
        "/api/plan",
        json={"prompt": "¿Qué tengo hoy?"},
        headers={"Authorization": "Bearer valid_mock_token"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["reply"] == "Tienes 2 reuniones agendadas hoy."
    assert len(data["actions"]) == 1
    assert data["actions"][0]["tool"] == "calendar_list_events"
    assert data["actions"][0]["status"] == "success"
    mock_agent_run.assert_called_once_with(
        prompt="¿Qué tengo hoy?",
        access_token="valid_mock_token"
    )


def test_auth_client_get_credentials():
    """Tests that auth_client creates Credentials from a token."""
    creds = get_credentials("sample_oauth_token")
    assert creds.token == "sample_oauth_token"


def test_workspace_tools_definition():
    """Verifies that all 8 Workspace tools are declared."""
    tool = build_workspace_tool()
    function_names = [f.name for f in tool.function_declarations]
    expected_tools = [
        "calendar_list_events",
        "calendar_create_event",
        "gmail_list_messages",
        "gmail_send_email",
        "tasks_list_tasks",
        "tasks_create_task",
        "docs_create_document",
        "drive_search_files"
    ]
    for expected in expected_tools:
        assert expected in function_names
