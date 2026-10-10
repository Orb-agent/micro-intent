"""
Authentication client for Google Workspace APIs using GIS Bearer Tokens.
"""
from typing import Optional
from fastapi import Header, HTTPException, status
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build, Resource


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


async def get_current_token(authorization: Optional[str] = Header(None)) -> str:
    """FastAPI dependency to extract Bearer token from Authorization header."""
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header is required"
        )
    
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization format. Expected 'Bearer <token>'"
        )
    
    return parts[1]
