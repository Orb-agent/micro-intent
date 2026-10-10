"""
Authentication client for Google Workspace APIs using GIS Bearer Tokens.
"""
import os
import time
from typing import Optional

import httpx
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build, Resource

bearer_auth = HTTPBearer(
    scheme_name="GoogleAccessToken",
    bearerFormat="Google OAuth2 access token",
    description=(
        "Paste a valid Google OAuth2 access token only (without the Bearer prefix). "
        "Use an access token from Google Identity Services with the scopes required "
        "by the endpoint; a Google ID token or Gemini API key will not work. "
        "Reading Gmail with a search query requires gmail.readonly or a broader Gmail scope."
    ),
    auto_error=False,
)


def get_credentials(access_token: str) -> Credentials:
    """Creates Google OAuth2 Credentials object from a GIS Bearer token."""
    if not access_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Google OAuth2 Access Token"
        )
    return Credentials(token=access_token)


def get_service(service_name: str, version: str, access_token: str) -> Resource:
    """Builds and returns an authorized Google API service resource."""
    try:
        credentials = get_credentials(access_token)
        return build(service_name, version, credentials=credentials, cache_discovery=False)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Error initializing Google service {service_name}: {str(e)}"
        )


async def get_current_token(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_auth),
) -> str:
    """FastAPI dependency to extract Bearer token from Authorization header."""
    authorization = request.headers.get("Authorization")
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header is required. In /docs, click Connect Gmail or Connect Calendar and grant access, or use Authorize with an existing Google OAuth2 access token.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    parts = authorization.split()
    if len(parts) != 2 or credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization format. Expected 'Bearer <token>'",
            headers={"WWW-Authenticate": "Bearer"},
        )

    await verify_google_token(parts[1])
    return parts[1]


TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"
# ponytail: grows by one entry per distinct live token; prune expired entries if the server runs for weeks
_verified: dict[str, float] = {}  # token -> expiry, epoch seconds


async def verify_google_token(token: str) -> None:
    """Accepts only live Google access tokens issued to this app's OAuth client (GOOGLE_CLIENT_ID).

    Without this, any string after Bearer would unlock the endpoints that spend the
    server's Gemini, Maps and SerpApi keys.
    """
    if _verified.get(token, 0) > time.time():
        return
    client_id = os.getenv("GOOGLE_CLIENT_ID")
    if not client_id:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="GOOGLE_CLIENT_ID is not set, so Google access tokens cannot be verified.",
        )
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(TOKENINFO_URL, data={"access_token": token})
    except httpx.HTTPError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not reach Google to verify the access token. Retry.",
        )
    info = resp.json() if resp.is_success else {}
    if client_id not in (info.get("aud"), info.get("azp")):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Google access token is invalid, expired, or was not issued to this app. Reconnect in /docs.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    _verified[token] = float(info.get("exp", 0))
