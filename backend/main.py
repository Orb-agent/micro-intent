"""
FastAPI Server for Lumi Executive Assistant Backend.
Integrates Google Identity Services (GIS) auth, Gemini Function Calling, and Google Workspace APIs.
"""
import os
from typing import Dict, Any, List, Optional
from dotenv import load_dotenv
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from services.auth_client import get_current_token
from services import (
    calendar_service,
    gmail_service,
    drive_service,
    docs_service,
    tasks_service,
)
from agent_engine import LumiAgent

load_dotenv()

app = FastAPI(
    title="Lumi Executive Assistant API",
    description="Backend API powered by Gemini and Google Workspace APIs",
    version="1.0.0"
)

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
class PlanRequest(BaseModel):
    prompt: str = Field(..., description="Instrucción u objetivo en lenguaje natural para Lumi")


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


# Endpoints
@app.get("/health")
def health_check():
    """Health check endpoint to verify backend status."""
    return {
        "status": "ok",
        "service": "Lumi Backend",
        "gemini_configured": bool(os.getenv("GEMINI_API_KEY"))
    }


@app.post("/api/plan", response_model=PlanResponse)
async def create_and_execute_plan(
    request: PlanRequest,
    access_token: str = Depends(get_current_token)
):
    """
    Main orchestration endpoint:
    Receives prompt and GIS Bearer token, invokes Gemini Function Calling to inspect,
    plan, and execute Google Workspace operations, returning synthesized response.
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


@app.post("/api/chat", response_model=PlanResponse)
async def chat_with_lumi(
    request: ChatRequest,
    access_token: str = Depends(get_current_token)
):
    """Conversational endpoint with Lumi with Workspace tool support."""
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


# Direct Helper Endpoints (Optional for frontend data inspection)
@app.get("/api/calendar/events")
async def get_calendar_events(
    max_results: int = 10,
    time_min: Optional[str] = None,
    access_token: str = Depends(get_current_token)
):
    """Directly lists calendar events for the authenticated user."""
    return calendar_service.list_events(access_token, max_results, time_min)


@app.get("/api/gmail/messages")
async def get_gmail_messages(
    query: str = "is:unread",
    max_results: int = 5,
    access_token: str = Depends(get_current_token)
):
    """Directly lists Gmail messages matching a search query."""
    return gmail_service.list_messages(access_token, query, max_results)


@app.get("/api/tasks")
async def get_tasks(
    tasklist: str = "@default",
    access_token: str = Depends(get_current_token)
):
    """Directly lists pending Google Tasks."""
    return tasks_service.list_tasks(access_token, tasklist)


@app.get("/api/drive/files")
async def get_drive_files(
    query: Optional[str] = None,
    page_size: int = 10,
    access_token: str = Depends(get_current_token)
):
    """Directly lists Google Drive files."""
    return drive_service.search_files(access_token, query, page_size)


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    host = os.getenv("HOST", "0.0.0.0")
    uvicorn.run("main:app", host=host, port=port, reload=True)
