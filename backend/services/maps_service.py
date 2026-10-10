"""
Google Maps service module for place searching, geocoding, directions, and navigation deep links.
Supports Google Maps Platform APIs (Places, Directions) when GOOGLE_MAPS_API_KEY is configured,
with resilient fallbacks to OpenStreetMap Nominatim and official Google Maps URL schemes.
"""
import os
import urllib.parse
from typing import List, Dict, Any, Optional
import httpx


GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY")


def get_maps_search_url(query: str) -> str:
    """Generates the official Google Maps search URL."""
    encoded_query = urllib.parse.quote(query)
    return f"https://www.google.com/maps/search/?api=1&query={encoded_query}"


def get_maps_directions_url(origin: str, destination: str, mode: str = "driving") -> str:
    """Generates the official Google Maps turn-by-turn directions URL."""
    valid_modes = {"driving", "transit", "walking", "bicycling"}
    travel_mode = mode if mode in valid_modes else "driving"
    encoded_origin = urllib.parse.quote(origin)
    encoded_dest = urllib.parse.quote(destination)
    return f"https://www.google.com/maps/dir/?api=1&origin={encoded_origin}&destination={encoded_dest}&travelmode={travel_mode}"


def search_places(
    query: str,
    location: Optional[str] = None,
    max_results: int = 5
) -> List[Dict[str, Any]]:
    """
    Searches for places, establishments, landmarks, or addresses.
    Uses Google Places API if GOOGLE_MAPS_API_KEY is provided, or OpenStreetMap Nominatim
    with official Google Maps deep links as fallback.
    """
    if not query or not query.strip():
        return []

    clean_query = query.strip()
    api_key = os.getenv("GOOGLE_MAPS_API_KEY") or GOOGLE_MAPS_API_KEY

    # 1. Try Google Places Text Search API if key is present
    if api_key:
        try:
            params = {
                "query": clean_query,
                "key": api_key,
            }
            if location:
                params["location"] = location

            with httpx.Client(timeout=4.0) as client:
                resp = client.get("https://maps.googleapis.com/maps/api/place/textsearch/json", params=params)
                if resp.status_code == 200:
                    data = resp.json()
                    status = data.get("status")
                    if status in ("OK", "ZERO_RESULTS"):
                        results = []
                        for item in data.get("results", [])[:max_results]:
                            name = item.get("name", clean_query)
                            address = item.get("formatted_address", "")
                            loc = item.get("geometry", {}).get("location", {})
                            place_id = item.get("place_id")

                            # Google Maps URL with place_id or query
                            if place_id:
                                maps_url = f"https://www.google.com/maps/search/?api=1&query={urllib.parse.quote(name)}&query_place_id={place_id}"
                            else:
                                maps_url = get_maps_search_url(f"{name} {address}".strip())

                            results.append({
                                "name": name,
                                "address": address,
                                "location": {"lat": loc.get("lat"), "lng": loc.get("lng")} if loc else None,
                                "rating": item.get("rating"),
                                "types": item.get("types", []),
                                "place_id": place_id,
                                "maps_url": maps_url,
                            })
                        if results:
                            return results
        except Exception:
            pass  # Fall back gracefully

    # 2. Resilient fallback using OpenStreetMap Nominatim + Google Maps URL
    try:
        headers = {"User-Agent": "LumiExecutiveAssistant/1.0 (hackathon-companion)"}
        params = {"q": clean_query, "format": "json", "limit": max_results}
        with httpx.Client(timeout=2.5, headers=headers) as client:
            resp = client.get("https://nominatim.openstreetmap.org/search", params=params)
            if resp.status_code == 200:
                items = resp.json()
                if isinstance(items, list) and len(items) > 0:
                    results = []
                    for item in items[:max_results]:
                        display_name = item.get("display_name", clean_query)
                        parts = display_name.split(",", 1)
                        name = parts[0].strip()
                        address = parts[1].strip() if len(parts) > 1 else display_name
                        lat = float(item["lat"]) if "lat" in item else None
                        lon = float(item["lon"]) if "lon" in item else None

                        results.append({
                            "name": name,
                            "address": address,
                            "location": {"lat": lat, "lng": lon} if lat and lon else None,
                            "rating": None,
                            "types": [item.get("type", "establishment")],
                            "place_id": str(item.get("place_id", "")),
                            "maps_url": get_maps_search_url(display_name),
                        })
                    return results
    except Exception:
        pass

    # 3. Direct Google Maps URL item fallback
    return [{
        "name": clean_query,
        "address": clean_query,
        "location": None,
        "rating": None,
        "types": ["place"],
        "place_id": None,
        "maps_url": get_maps_search_url(clean_query),
    }]


def get_directions(
    origin: str,
    destination: str,
    mode: str = "driving"
) -> Dict[str, Any]:
    """
    Calculates route navigation between origin and destination.
    Uses Google Directions API if GOOGLE_MAPS_API_KEY is configured,
    or generates structured routing with the official Google Maps navigation URL.
    """
    valid_modes = {"driving", "transit", "walking", "bicycling"}
    travel_mode = mode if mode in valid_modes else "driving"
    maps_url = get_maps_directions_url(origin, destination, travel_mode)
    api_key = os.getenv("GOOGLE_MAPS_API_KEY") or GOOGLE_MAPS_API_KEY

    # 1. Try Google Directions API if key configured
    if api_key:
        try:
            params = {
                "origin": origin,
                "destination": destination,
                "mode": travel_mode,
                "key": api_key,
            }
            with httpx.Client(timeout=4.0) as client:
                resp = client.get("https://maps.googleapis.com/maps/api/directions/json", params=params)
                if resp.status_code == 200:
                    data = resp.json()
                    if data.get("status") == "OK" and data.get("routes"):
                        route = data["routes"][0]
                        leg = route["legs"][0] if route.get("legs") else {}

                        distance_text = leg.get("distance", {}).get("text", "N/A")
                        duration_text = leg.get("duration", {}).get("text", "N/A")
                        duration_val = leg.get("duration", {}).get("value")
                        start_addr = leg.get("start_address", origin)
                        end_addr = leg.get("end_address", destination)

                        steps = []
                        for s in leg.get("steps", []):
                            # strip HTML tags if any
                            raw_instr = s.get("html_instructions", "")
                            instr = raw_instr.replace("<b>", "").replace("</b>", "").replace('<div style="font-size:0.9em">', " ").replace("</div>", "")
                            steps.append({
                                "instruction": instr,
                                "distance": s.get("distance", {}).get("text", ""),
                                "duration": s.get("duration", {}).get("text", "")
                            })

                        return {
                            "origin": start_addr,
                            "destination": end_addr,
                            "mode": travel_mode,
                            "distance": distance_text,
                            "duration": duration_text,
                            "duration_seconds": duration_val,
                            "summary": route.get("summary") or f"Route from {start_addr} to {end_addr}",
                            "maps_url": maps_url,
                            "steps": steps
                        }
        except Exception:
            pass  # Fall back gracefully

    # 2. Resilient structured route estimation with Google Maps navigation link
    return {
        "origin": origin,
        "destination": destination,
        "mode": travel_mode,
        "distance": "Calculated in Google Maps",
        "duration": "Live navigation available in Google Maps",
        "duration_seconds": None,
        "summary": f"Route from {origin} to {destination} ({travel_mode})",
        "maps_url": maps_url,
        "steps": [
            {
                "instruction": f"Start from {origin}",
                "distance": "",
                "duration": ""
            },
            {
                "instruction": f"Head towards {destination} via {travel_mode}",
                "distance": "",
                "duration": ""
            },
            {
                "instruction": f"Arrive at {destination}",
                "distance": "",
                "duration": ""
            }
        ]
    }
