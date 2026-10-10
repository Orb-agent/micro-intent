"""
Authentication client for Google Workspace APIs using GIS Bearer Tokens.
"""
from typing import Optional
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
    
    return parts[1]
