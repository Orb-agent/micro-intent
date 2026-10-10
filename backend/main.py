"""
FastAPI Server for Lumi Executive Assistant Backend.
Integrates Google Identity Services (GIS) auth, Gemini Function Calling, Google Workspace APIs,
Google Maps, and Google Flights.
"""
import os
from pathlib import Path
from typing import Dict, Any, List, Optional
from dotenv import load_dotenv
from fastapi import FastAPI, Depends, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from googleapiclient.errors import HttpError
from pydantic import BaseModel, ConfigDict, Field

from services.auth_client import get_current_token
from services import (
    calendar_service,
    gmail_service,
    drive_service,
    docs_service,
    tasks_service,
    maps_service,
    flights_service,
)
from agent_engine import LumiAgent
from services.docs_auth import google_docs_html

backend_dir = Path(__file__).resolve().parent
load_dotenv(backend_dir / ".env")
load_dotenv(backend_dir.parent / ".env")

app = FastAPI(
    title="Lumi Executive Assistant API",
    description=(
        "Backend API powered by Gemini, Google Workspace, Google Maps, and Google Flights. "
        "To try Gmail or Calendar, use the **Connect Gmail** or **Connect Calendar** "
        "button above and grant Google access. Alternatively, click **Authorize** and paste a Google OAuth2 "
        "access token without the Bearer prefix. The token must have the Workspace "
        "scopes required by the endpoint. Google ID tokens and Gemini API keys are not access tokens."
    ),
    version="1.0.0",
    docs_url=None,
)


@app.get("/docs", include_in_schema=False)
async def interactive_docs():
    return google_docs_html()


@app.exception_handler(HttpError)
async def google_api_error_handler(request, exc: HttpError):
    code = exc.resp.status
    headers = {}
    if code == 401:
        detail = "Google access has expired or is invalid. Reconnect using Connect Gmail or Connect Calendar in /docs."
        headers["WWW-Authenticate"] = "Bearer"
    elif code == 403:
        detail = "Google denied access. Grant the required service permission, enable its API in Google Cloud, and check account or administrator restrictions."
    elif code == 429:
        detail = "Google API rate limit reached. Wait and retry."
    else:
        code = 502
        detail = "The Google API request failed. Retry or check the service configuration."
    return JSONResponse(status_code=code, content={"detail": detail}, headers=headers)

# CORS configuration
raw_origins = os.getenv(
    "CORS_ORIGINS",
    "http://localhost:3000,http://localhost:5173,http://127.0.0.1:3000,http://127.0.0.1:5173"
)
origins = [origin.strip() for origin in raw_origins.split(",") if origin.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Lumi Agent
agent = LumiAgent()


# Request & Response Schemas
class ErrorResponse(BaseModel):
    detail: str


AUTH_RESPONSES = {
    401: {
        "model": ErrorResponse,
        "description": "Missing, malformed, expired, or invalid Google access token. Connect Google in /docs.",
        "headers": {"WWW-Authenticate": {"schema": {"type": "string"}}},
    },
    403: {"model": ErrorResponse, "description": "Google permission missing, API disabled, or account access restricted."},
    429: {"model": ErrorResponse, "description": "Google API rate limit reached."},
    502: {"model": ErrorResponse, "description": "Google API request failed."},
}


class GmailMessage(BaseModel):
    id: str
    snippet: str
    subject: str
    sender: str = Field(alias="from")
    date: str


class PlanRequest(BaseModel):
    prompt: str = Field(..., description="Natural-language instruction or objective for Lumi")


class ActionExecuted(BaseModel):
    tool: str
    arguments: Dict[str, Any]
    status: str
    result: Optional[Any] = None
    error: Optional[str] = None


class PlanResponse(BaseModel):
    reply: str
    actions: List[ActionExecuted]


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    message: str
    history: Optional[List[ChatMessage]] = None


# Google Maps & Google Flights Schemas
class PlaceLocation(BaseModel):
    lat: Optional[float] = None
    lng: Optional[float] = None


class PlaceResult(BaseModel):
    name: str
    address: str
    location: Optional[PlaceLocation] = None
    rating: Optional[float] = None
    types: List[str] = Field(default_factory=list)
    place_id: Optional[str] = None
    maps_url: str


class DirectionStep(BaseModel):
    instruction: str
    distance: str = ""
    duration: str = ""


class DirectionsResponse(BaseModel):
    origin: str
    destination: str
    mode: str
    distance: str
    duration: str
    duration_seconds: Optional[int] = None
    summary: str
    maps_url: str
    steps: List[DirectionStep] = Field(default_factory=list)


class FlightOption(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    flight_number: str
    airline: str
    from_airport: str = Field(alias="from")
    to_airport: str = Field(alias="to")
    departure: str
    arrival: str
    duration: Optional[str] = None
    stops: int = 0
    price_estimate: Optional[str] = None
    google_flights_url: str


class FlightSearchResponse(BaseModel):
    search_query: str
    origin: str
    destination: str
    departure_date: str
    return_date: Optional[str] = None
    passengers: int
    travel_class: str
    google_flights_url: str
    flights: List[FlightOption] = Field(default_factory=list)


class FlightReservation(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    flight_number: Optional[str] = None
    airline: Optional[str] = None
    from_airport: Optional[str] = Field(None, alias="from")
    to_airport: Optional[str] = Field(None, alias="to")
    departure: Optional[str] = None
    arrival: Optional[str] = None
    booking_ref: Optional[str] = None
    email_subject: Optional[str] = None
    email_date: Optional[str] = None
    google_flights_url: Optional[str] = None


# Endpoints
@app.get("/health")
def health_check():
    """Health check endpoint to verify backend status."""
    return {
        "status": "ok",
        "service": "Lumi Backend",
        "gemini_configured": bool(os.getenv("GEMINI_API_KEY")),
        "google_maps_configured": bool(os.getenv("GOOGLE_MAPS_API_KEY")),
        "serpapi_configured": bool(os.getenv("SERPAPI_API_KEY")),
    }


@app.post("/api/plan", response_model=PlanResponse, responses=AUTH_RESPONSES)
async def create_and_execute_plan(
    request: PlanRequest,
    access_token: str = Depends(get_current_token)
):
    """
    Main orchestration endpoint:
    Receives prompt and GIS Bearer token, invokes Gemini Function Calling to inspect,
    plan, and execute Google Workspace, Maps, and Flights operations, returning synthesized response.
    """
    if not request.prompt or not request.prompt.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Prompt cannot be empty"
        )

    try:
        result = agent.run(prompt=request.prompt, access_token=access_token)
        return PlanResponse(
            reply=result["reply"],
            actions=result["actions"]
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Agent orchestration failed: {str(e)}"
        )


@app.post("/api/chat", response_model=PlanResponse, responses=AUTH_RESPONSES)
async def chat_with_lumi(
    request: ChatRequest,
    access_token: str = Depends(get_current_token)
):
    """Conversational endpoint with Lumi with Workspace, Maps, and Flights tool support."""
    if not request.message or not request.message.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Message cannot be empty"
        )

    try:
        result = agent.run(prompt=request.message, access_token=access_token)
        return PlanResponse(
            reply=result["reply"],
            actions=result["actions"]
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Chat error: {str(e)}"
        )


# Direct Helper Endpoints
@app.get("/api/calendar/events", response_model=List[Dict[str, Any]], responses=AUTH_RESPONSES)
async def get_calendar_events(
    max_results: int = 10,
    time_min: Optional[str] = None,
    access_token: str = Depends(get_current_token)
):
    """Directly lists calendar events for the authenticated user."""
    return calendar_service.list_events(access_token, max_results, time_min)


@app.get("/api/gmail/messages", response_model=List[GmailMessage], responses=AUTH_RESPONSES)
async def get_gmail_messages(
    query: str = "is:unread",
    max_results: int = Query(5, ge=1, le=500),
    access_token: str = Depends(get_current_token)
):
    """Lists Gmail messages matching a search query. Click Connect Gmail above and
    grant read access before executing, or use Authorize with an existing access token.
    """
    return gmail_service.list_messages(access_token, query, max_results)


@app.get("/api/tasks", responses=AUTH_RESPONSES)
async def get_tasks(
    tasklist: str = "@default",
    access_token: str = Depends(get_current_token)
):
    """Directly lists pending Google Tasks."""
    return tasks_service.list_tasks(access_token, tasklist)


@app.get("/api/drive/files", responses=AUTH_RESPONSES)
async def get_drive_files(
    query: Optional[str] = None,
    page_size: int = 10,
    access_token: str = Depends(get_current_token)
):
    """Directly lists Google Drive files."""
    return drive_service.search_files(access_token, query, page_size)


@app.get("/api/maps/search", response_model=List[PlaceResult], responses=AUTH_RESPONSES)
async def search_maps_places(
    query: str = Query(..., description="Search term or place to find on Google Maps"),
    location: Optional[str] = Query(None, description="Optional location or coordinates"),
    max_results: int = Query(5, ge=1, le=20, description="Maximum number of results"),
    access_token: str = Depends(get_current_token)
):
    """Searches for places, addresses, or points of interest on Google Maps."""
    return maps_service.search_places(query=query, location=location, max_results=max_results)


@app.get("/api/maps/directions", response_model=DirectionsResponse, responses=AUTH_RESPONSES)
async def get_maps_directions(
    origin: str = Query(..., description="Starting point or origin address"),
    destination: str = Query(..., description="Arrival point or destination"),
    mode: str = Query("driving", pattern="^(driving|transit|walking|bicycling)$", description="Travel mode"),
    access_token: str = Depends(get_current_token)
):
    """Calculates navigation route, estimated time, and official Google Maps directions URL."""
    return maps_service.get_directions(origin=origin, destination=destination, mode=mode)


@app.get("/api/flights/search", response_model=FlightSearchResponse, responses=AUTH_RESPONSES)
async def search_google_flights(
    origin: str = Query(..., description="Origin airport or city (e.g., ZRH)"),
    destination: str = Query(..., description="Destination airport or city (e.g., LIS)"),
    departure_date: str = Query(..., description="Departure date in YYYY-MM-DD format"),
    return_date: Optional[str] = Query(None, description="Optional return date in YYYY-MM-DD format"),
    passengers: int = Query(1, ge=1, le=9, description="Number of passengers"),
    travel_class: str = Query("economy", description="Travel class ('economy', 'business', etc.)"),
    access_token: str = Depends(get_current_token)
):
    """Searches flights and generates official Google Flights search and booking links."""
    return flights_service.search_flights(
        origin=origin,
        destination=destination,
        departure_date=departure_date,
        return_date=return_date,
        passengers=passengers,
        travel_class=travel_class
    )


@app.get("/api/flights/reservations", response_model=List[FlightReservation], responses=AUTH_RESPONSES)
async def get_flight_reservations(
    query: str = Query("flight OR booking OR airline OR ticket OR boarding", description="Search query for flight emails"),
    access_token: str = Depends(get_current_token)
):
    """Retrieves flight reservations, tickets, booking codes (PNR), and flight numbers from Gmail."""
    return flights_service.get_user_flight_reservations(access_token=access_token, query=query)


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    host = os.getenv("HOST", "0.0.0.0")
    uvicorn.run("main:app", host=host, port=port, reload=True)
