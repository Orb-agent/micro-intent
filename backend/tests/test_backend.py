"""
Automated unit & integration tests for the Lumi Backend.
"""
import pytest
from httplib2 import Response
from googleapiclient.errors import HttpError
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient

from main import app
from services.auth_client import get_credentials
from services import maps_service, flights_service
from agent_engine import build_workspace_tool, dispatch_tool_call

client = TestClient(app)


def test_docs_google_connection(monkeypatch):
    monkeypatch.setenv("GOOGLE_CLIENT_ID", "test-client.apps.googleusercontent.com")
    response = client.get("/docs")
    assert response.status_code == 200
    assert 'id="connect-gmail"' in response.text
    assert 'id="connect-calendar"' in response.text
    assert "test-client.apps.googleusercontent.com" in response.text
    assert "https://accounts.google.com/gsi/client" in response.text
    assert response.headers["cache-control"] == "no-store"


def test_docs_without_client_id(monkeypatch):
    monkeypatch.delenv("GOOGLE_CLIENT_ID", raising=False)
    response = client.get("/docs")
    assert response.status_code == 200
    assert '"clientId": ""' in response.text


@pytest.mark.parametrize("google_status,expected", [(401, 401), (403, 403), (429, 429), (500, 502)])
@patch("main.gmail_service.list_messages")
def test_google_errors_are_actionable(mock_list, google_status, expected):
    mock_list.side_effect = HttpError(
        Response({"status": google_status}),
        b'{"error":{"message":"private provider details"}}',
    )
    response = client.get("/api/gmail/messages", headers={"Authorization": "Bearer test-token"})
    assert response.status_code == expected
    assert "Google" in response.json()["detail"]
    assert "private provider details" not in response.text
    if expected == 401:
        assert response.headers["WWW-Authenticate"] == "Bearer"


def test_openapi_bearer_authorization():
    schema = client.get("/openapi.json").json()
    security = schema["components"]["securitySchemes"]["GoogleAccessToken"]
    assert security["type"] == "http"
    assert security["scheme"] == "bearer"
    for path, methods in schema["paths"].items():
        if not path.startswith("/api/"):
            continue
        for operation in methods.values():
            assert operation["security"] == [{"GoogleAccessToken": []}]
            assert "401" in operation["responses"]
            assert not any(
                p["name"].lower() == "authorization"
                for p in operation.get("parameters", [])
            )
    gmail = schema["paths"]["/api/gmail/messages"]["get"]
    assert gmail["responses"]["200"]["content"]["application/json"]["schema"]["type"] == "array"
    assert "security" not in schema["paths"]["/health"]["get"]


@pytest.mark.parametrize("authorization", [None, "", "Basic token", "Bearer", "Bearer one two"])
@patch("main.gmail_service.list_messages")
def test_gmail_requires_bearer_token(mock_list, authorization):
    headers = {} if authorization is None else {"Authorization": authorization}
    response = client.get("/api/gmail/messages", headers=headers)
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"
    mock_list.assert_not_called()


@pytest.mark.parametrize("scheme", ["Bearer", "bearer"])
@patch("main.gmail_service.list_messages")
def test_gmail_authenticated_request(mock_list, scheme):
    messages = [{"id": "123", "snippet": "Hello", "subject": "Test", "from": "test@example.com", "date": "today"}]
    mock_list.return_value = messages
    response = client.get(
        "/api/gmail/messages?query=is%3Aunread&max_results=5",
        headers={"Authorization": f"{scheme} mock_google_access_token"},
    )
    assert response.status_code == 200
    assert response.json() == messages
    mock_list.assert_called_once_with("mock_google_access_token", "is:unread", 5)


@pytest.mark.parametrize("limit", [0, -1, 501])
@patch("main.gmail_service.list_messages")
def test_gmail_rejects_invalid_limit(mock_list, limit):
    response = client.get(
        f"/api/gmail/messages?max_results={limit}",
        headers={"Authorization": "Bearer mock_google_access_token"},
    )
    assert response.status_code == 422
    mock_list.assert_not_called()


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
    response = client.post("/api/plan", json={"prompt": "Check my email"})
    assert response.status_code == 401
    assert "Authorization header is required" in response.json()["detail"]


def test_plan_invalid_token_format():
    """Checks that /api/plan rejects malformed Authorization headers."""
    response = client.post(
        "/api/plan",
        json={"prompt": "Check my email"},
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
        "reply": "You have 2 meetings scheduled today.",
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
        json={"prompt": "What's on my schedule today?"},
        headers={"Authorization": "Bearer valid_mock_token"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["reply"] == "You have 2 meetings scheduled today."
    assert len(data["actions"]) == 1
    assert data["actions"][0]["tool"] == "calendar_list_events"
    assert data["actions"][0]["status"] == "success"
    mock_agent_run.assert_called_once_with(
        prompt="What's on my schedule today?",
        access_token="valid_mock_token"
    )


def test_auth_client_get_credentials():
    """Tests that auth_client creates Credentials from a token."""
    creds = get_credentials("sample_oauth_token")
    assert creds.token == "sample_oauth_token"


def test_workspace_tools_definition():
    """Verifies that Workspace, Google Maps, and Google Flights tools are declared."""
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
        "drive_search_files",
        "maps_search_places",
        "maps_get_directions",
        "flights_search",
        "flights_get_reservations",
    ]
    for expected in expected_tools:
        assert expected in function_names, f"Missing tool: {expected}"


# ==================== Google Maps Service & Endpoints Tests ====================

def test_maps_service_get_search_url():
    url = maps_service.get_maps_search_url("Google Zurich")
    assert "https://www.google.com/maps/search/?api=1&query=" in url
    assert "Google%20Zurich" in url


def test_maps_service_get_directions_url():
    url = maps_service.get_maps_directions_url("Zürich HB", "Bern", "transit")
    assert "https://www.google.com/maps/dir/?api=1&origin=" in url
    assert "travelmode=transit" in url


def test_maps_service_search_places():
    places = maps_service.search_places("Google Zurich")
    assert len(places) > 0
    first = places[0]
    assert "name" in first
    assert "maps_url" in first
    assert "https://www.google.com/maps/search/" in first["maps_url"]


def test_maps_service_get_directions():
    route = maps_service.get_directions("Zürich HB", "Bern", "driving")
    assert route["origin"] == "Zürich HB"
    assert route["destination"] == "Bern"
    assert route["mode"] == "driving"
    assert "maps_url" in route
    assert len(route["steps"]) > 0


@patch("main.maps_service.search_places")
def test_api_maps_search_authenticated(mock_search):
    mock_search.return_value = [
        {
            "name": "Google Zurich",
            "address": "Europaallee 20, 8004 Zürich",
            "location": {"lat": 47.3782, "lng": 8.5345},
            "rating": 4.6,
            "types": ["office"],
            "place_id": "ChIJ123",
            "maps_url": "https://www.google.com/maps/search/?api=1&query=Google+Zurich",
        }
    ]
    response = client.get(
        "/api/maps/search?query=Google+Zurich&max_results=5",
        headers={"Authorization": "Bearer test_access_token"},
    )
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["name"] == "Google Zurich"
    assert data[0]["location"]["lat"] == 47.3782
    mock_search.assert_called_once_with(query="Google Zurich", location=None, max_results=5)


@patch("main.maps_service.get_directions")
def test_api_maps_directions_authenticated(mock_directions):
    mock_directions.return_value = {
        "origin": "Zürich HB",
        "destination": "Bern",
        "mode": "transit",
        "distance": "125 km",
        "duration": "57 mins",
        "duration_seconds": 3420,
        "summary": "Fastest transit via IC 8",
        "maps_url": "https://www.google.com/maps/dir/?api=1&origin=Z%C3%BCrich+HB&destination=Bern&travelmode=transit",
        "steps": [{"instruction": "Depart from Zürich HB", "distance": "125 km", "duration": "57 mins"}],
    }
    response = client.get(
        "/api/maps/directions?origin=Z%C3%BCrich+HB&destination=Bern&mode=transit",
        headers={"Authorization": "Bearer test_access_token"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["origin"] == "Zürich HB"
    assert data["destination"] == "Bern"
    assert data["mode"] == "transit"
    assert data["distance"] == "125 km"


# ==================== Google Flights Service & Endpoints Tests ====================

def test_flights_service_build_url():
    url_oneway = flights_service.build_google_flights_url("ZRH", "LIS", "2026-10-20")
    assert "https://www.google.com/travel/flights?q=" in url_oneway
    assert "ZRH" in url_oneway and "LIS" in url_oneway

    url_round = flights_service.build_google_flights_url("ZRH", "LIS", "2026-10-20", "2026-10-27")
    assert "through" in url_round


def test_flights_service_search():
    result = flights_service.search_flights(
        origin="ZRH",
        destination="LIS",
        departure_date="2026-10-20",
        passengers=1,
        travel_class="economy"
    )
    assert result["origin"] == "ZRH"
    assert result["destination"] == "LIS"
    assert "google_flights_url" in result
    assert len(result["flights"]) > 0
    flight = result["flights"][0]
    assert flight["from"] == "ZRH"
    assert flight["to"] == "LIS"
    assert "flight_number" in flight
    assert "google_flights_url" in flight


@patch("services.flights_service.gmail_service.list_messages")
def test_flights_service_get_reservations_from_gmail(mock_list):
    mock_list.return_value = [
        {
            "id": "msg_swiss_1",
            "subject": "Your booking K7Q2ZP: Zürich – Lisbon",
            "snippet": "SWISS Flight LX 1820 departing ZRH to LIS on 2026-10-20T07:10:00+02:00. PNR: K7Q2ZP",
            "from": "SWISS",
            "date": "2026-10-09",
        }
    ]
    reservations = flights_service.get_user_flight_reservations("test_access_token")
    assert len(reservations) == 1
    res = reservations[0]
    assert res["flight_number"] == "LX 1820"
    assert res["airline"] == "SWISS"
    assert res["booking_ref"] == "K7Q2ZP"
    assert res["from"] == "ZRH"
    assert res["to"] == "LIS"
    assert "https://www.google.com/travel/flights?q=" in res["google_flights_url"]


@patch("main.flights_service.search_flights")
def test_api_flights_search_authenticated(mock_search):
    mock_search.return_value = {
        "search_query": "Flights from ZRH to LIS on 2026-10-20",
        "origin": "ZRH",
        "destination": "LIS",
        "departure_date": "2026-10-20",
        "return_date": None,
        "passengers": 1,
        "travel_class": "economy",
        "google_flights_url": "https://www.google.com/travel/flights?q=Flights%20from%20ZRH%20to%20LIS",
        "flights": [
            {
                "flight_number": "LX 1820",
                "airline": "SWISS",
                "from": "ZRH",
                "to": "LIS",
                "departure": "2026-10-20T07:10:00+02:00",
                "arrival": "2026-10-20T09:15:00+01:00",
                "duration": "2h 45m",
                "stops": 0,
                "price_estimate": "180 CHF",
                "google_flights_url": "https://www.google.com/travel/flights?q=SWISS+LX1820",
            }
        ],
    }
    response = client.get(
        "/api/flights/search?origin=ZRH&destination=LIS&departure_date=2026-10-20",
        headers={"Authorization": "Bearer test_access_token"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["origin"] == "ZRH"
    assert len(data["flights"]) == 1
    assert data["flights"][0]["from"] == "ZRH"
    assert data["flights"][0]["to"] == "LIS"


@patch("main.flights_service.get_user_flight_reservations")
def test_api_flights_reservations_authenticated(mock_res):
    mock_res.return_value = [
        {
            "flight_number": "LX 1820",
            "airline": "SWISS",
            "from": "ZRH",
            "to": "LIS",
            "departure": "2026-10-20T07:10:00+02:00",
            "arrival": "2026-10-20T09:15:00+01:00",
            "booking_ref": "K7Q2ZP",
            "email_subject": "Your booking K7Q2ZP",
            "email_date": "2026-10-09",
            "google_flights_url": "https://www.google.com/travel/flights?q=SWISS+LX+1820",
        }
    ]
    response = client.get(
        "/api/flights/reservations",
        headers={"Authorization": "Bearer test_access_token"},
    )
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["flight_number"] == "LX 1820"
    assert data[0]["booking_ref"] == "K7Q2ZP"


# ==================== Agent Tool Dispatch Tests ====================

@patch("agent_engine.maps_service.search_places")
def test_dispatch_maps_search_places(mock_maps_search):
    mock_maps_search.return_value = [{"name": "Google Zurich"}]
    res = dispatch_tool_call("maps_search_places", {"query": "Google Zurich", "max_results": 3}, "token")
    assert res == [{"name": "Google Zurich"}]
    mock_maps_search.assert_called_once_with(query="Google Zurich", location=None, max_results=3)


@patch("agent_engine.maps_service.get_directions")
def test_dispatch_maps_get_directions(mock_maps_dir):
    mock_maps_dir.return_value = {"distance": "125 km"}
    res = dispatch_tool_call("maps_get_directions", {"origin": "ZRH", "destination": "Bern", "mode": "transit"}, "token")
    assert res == {"distance": "125 km"}
    mock_maps_dir.assert_called_once_with(origin="ZRH", destination="Bern", mode="transit")


@patch("agent_engine.flights_service.search_flights")
def test_dispatch_flights_search(mock_flights_search):
    mock_flights_search.return_value = {"flights": [{"flight_number": "LX 1820"}]}
    res = dispatch_tool_call(
        "flights_search",
        {"origin": "ZRH", "destination": "LIS", "departure_date": "2026-10-20"},
        "token"
    )
    assert "flights" in res
    mock_flights_search.assert_called_once_with(
        origin="ZRH",
        destination="LIS",
        departure_date="2026-10-20",
        return_date=None,
        passengers=1,
        travel_class="economy"
    )


@patch("agent_engine.flights_service.get_user_flight_reservations")
def test_dispatch_flights_get_reservations(mock_flights_res):
    mock_flights_res.return_value = [{"booking_ref": "K7Q2ZP"}]
    res = dispatch_tool_call("flights_get_reservations", {}, "test_token")
    assert res == [{"booking_ref": "K7Q2ZP"}]
    mock_flights_res.assert_called_once_with(
        access_token="test_token",
        query="flight OR booking OR airline OR ticket OR boarding"
    )


@pytest.mark.parametrize("endpoint", [
    "/api/maps/search?query=Zurich",
    "/api/maps/directions?origin=Zurich&destination=Bern",
    "/api/flights/search?origin=ZRH&destination=LIS&departure_date=2026-10-20",
    "/api/flights/reservations",
])
def test_maps_and_flights_require_bearer_token(endpoint):
    response = client.get(endpoint)
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"
