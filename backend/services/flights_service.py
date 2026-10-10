"""
Google Flights service module for flight searching, Google Flights deep links,
and flight reservation retrieval from user's Gmail.
"""
import os
import re
import urllib.parse
from typing import List, Dict, Any, Optional
import httpx
from . import gmail_service


# Known airline prefixes and names
AIRLINES_MAP = {
    "LX": "SWISS",
    "LH": "Lufthansa",
    "IB": "Iberia",
    "TP": "TAP Air Portugal",
    "AF": "Air France",
    "KL": "KLM",
    "BA": "British Airways",
    "U2": "easyJet",
    "FR": "Ryanair",
    "VY": "Vueling",
    "AA": "American Airlines",
    "DL": "Delta Air Lines",
    "UA": "United Airlines",
}

# Known major airport codes to city mapping
AIRPORTS_MAP = {
    "ZRH": "Zürich",
    "LIS": "Lisbon",
    "MAD": "Madrid",
    "BCN": "Barcelona",
    "LHR": "London",
    "CDG": "Paris",
    "BER": "Berlin",
    "GVA": "Geneva",
    "FCO": "Rome",
    "AMS": "Amsterdam",
    "JFK": "New York",
    "LAX": "Los Angeles",
}


def build_google_flights_url(
    origin: str,
    destination: str,
    departure_date: Optional[str] = None,
    return_date: Optional[str] = None
) -> str:
    """Builds the official Google Flights search link."""
    clean_orig = origin.strip().upper()
    clean_dest = destination.strip().upper()

    if departure_date and return_date:
        query_text = f"Flights from {clean_orig} to {clean_dest} on {departure_date} through {return_date}"
    elif departure_date:
        query_text = f"Flights from {clean_orig} to {clean_dest} on {departure_date}"
    else:
        query_text = f"Flights from {clean_orig} to {clean_dest}"

    return f"https://www.google.com/travel/flights?q={urllib.parse.quote(query_text)}"


def search_flights(
    origin: str,
    destination: str,
    departure_date: str,
    return_date: Optional[str] = None,
    passengers: int = 1,
    travel_class: str = "economy"
) -> Dict[str, Any]:
    """
    Searches for flights on Google Flights.
    If SERPAPI_API_KEY is configured, calls the SerpApi Google Flights engine.
    Otherwise, or if SerpApi fails, returns no flights and only the Google Flights search link.
    """
    clean_orig = origin.strip().upper()
    clean_dest = destination.strip().upper()
    google_flights_url = build_google_flights_url(clean_orig, clean_dest, departure_date, return_date)

    serpapi_key = os.getenv("SERPAPI_API_KEY")
    if serpapi_key:
        try:
            params = {
                "engine": "google_flights",
                "departure_id": clean_orig,
                "arrival_id": clean_dest,
                "outbound_date": departure_date,
                "currency": "EUR",
                "hl": "en",
                "api_key": serpapi_key,
            }
            if return_date:
                params["return_date"] = return_date

            with httpx.Client(timeout=5.0) as client:
                resp = client.get("https://serpapi.com/search.json", params=params)
                if resp.status_code == 200:
                    data = resp.json()
                    best_flights = data.get("best_flights", []) or data.get("other_flights", [])
                    formatted_flights = []
                    for group in best_flights[:5]:
                        flights_info = group.get("flights", [])
                        if not flights_info:
                            continue
                        first_leg = flights_info[0]
                        last_leg = flights_info[-1]

                        airline = first_leg.get("airline", "Airline")
                        flight_no = first_leg.get("flight_number", "")
                        dep_time = first_leg.get("departure_airport", {}).get("time", departure_date)
                        arr_time = last_leg.get("arrival_airport", {}).get("time", departure_date)
                        price = group.get("price")
                        duration_mins = group.get("total_duration")

                        duration_str = f"{duration_mins // 60}h {duration_mins % 60}m" if duration_mins else "Direct"

                        formatted_flights.append({
                            "flight_number": flight_no or f"{airline[:2].upper()} Flight",
                            "airline": airline,
                            "from": clean_orig,
                            "to": clean_dest,
                            "departure": dep_time,
                            "arrival": arr_time,
                            "duration": duration_str,
                            "stops": len(flights_info) - 1,
                            "price_estimate": f"{price} EUR" if price else "Ver en Google Flights",
                            "google_flights_url": google_flights_url,
                        })

                    if formatted_flights:
                        return {
                            "search_query": f"Flights from {clean_orig} to {clean_dest} on {departure_date}",
                            "origin": clean_orig,
                            "destination": clean_dest,
                            "departure_date": departure_date,
                            "return_date": return_date,
                            "passengers": passengers,
                            "travel_class": travel_class,
                            "google_flights_url": google_flights_url,
                            "flights": formatted_flights,
                        }
        except Exception:
            pass  # No live data: return the search link only, never invented flights

    return {
        "search_query": f"Flights from {clean_orig} to {clean_dest} on {departure_date}",
        "origin": clean_orig,
        "destination": clean_dest,
        "departure_date": departure_date,
        "return_date": return_date,
        "passengers": passengers,
        "travel_class": travel_class,
        "google_flights_url": google_flights_url,
        "flights": [],
    }


def get_user_flight_reservations(
    access_token: str,
    query: str = "flight OR booking OR airline OR ticket OR boarding"
) -> List[Dict[str, Any]]:
    """
    Inspects user's Gmail to find flight reservations, booking references, and itineraries.
    Extracts flight numbers, airlines, routes, and booking codes, providing Google Flights tracking links.
    """
    messages = gmail_service.list_messages(access_token, query=query, max_results=10)
    reservations = []

    # Regex patterns for flight detection
    pnr_pattern = re.compile(r'\b([A-Z0-9]{6})\b')
    flight_pattern = re.compile(r'\b([A-Z]{2}|[A-Z]\d|\d[A-Z])\s?(\d{2,4})\b')
    iata_pattern = re.compile(r'\b([A-Z]{3})\b')

    for msg in messages:
        subject = msg.get("subject", "")
        snippet = msg.get("snippet", "")
        combined_text = f"{subject} {snippet}"

        # Check if text contains flight keywords
        is_flight_related = any(k in combined_text.lower() for k in [
            "flight", "booking", "airline", "ticket", "boarding",
            "pnr", "swiss", "lufthansa", "iberia", "tap"
        ])

        if not is_flight_related:
            continue

        # Extract PNR / booking reference
        booking_ref = None
        # Look for "booking K7Q2ZP", "ref: K7Q2ZP", "reference: K7Q2ZP", or "PNR: K7Q2ZP"
        ref_match = re.search(r'(?:booking|ref|reference|pnr|code)[:\s]+([A-Z0-9]{6})\b', combined_text, re.IGNORECASE)
        if ref_match:
            booking_ref = ref_match.group(1).upper()
        else:
            # Check subject for standalone 6-char alphanumeric
            pnr_candidates = pnr_pattern.findall(subject)
            if pnr_candidates:
                booking_ref = pnr_candidates[0]

        # Extract Flight Number
        flight_number = None
        flight_matches = flight_pattern.findall(combined_text)
        airline = None
        if flight_matches:
            airline_code, num = flight_matches[0]
            airline_code = airline_code.upper()
            flight_number = f"{airline_code} {num}"
            airline = AIRLINES_MAP.get(airline_code)

        # Detect airline if not found by code
        if not airline:
            for code, name in AIRLINES_MAP.items():
                if name.lower() in combined_text.lower():
                    airline = name
                    break

        # Extract Origin and Destination (look for "ZRH to LIS" or "Zürich – Lisbon")
        origin = None
        destination = None
        route_match = re.search(r'([A-Za-z\s]+)\s*(?:–|-|to|->)\s*([A-Za-z\s]+)', subject)
        if route_match:
            cand_from = route_match.group(1).strip()
            cand_to = route_match.group(2).strip()

            # Map city or check IATA
            for code, city in AIRPORTS_MAP.items():
                if city.lower() in cand_from.lower() or code.lower() in cand_from.lower():
                    origin = code
                if city.lower() in cand_to.lower() or code.lower() in cand_to.lower():
                    destination = code

        # Fallback to searching 3-letter IATA codes
        if not origin or not destination:
            found_iatas = [c for c in iata_pattern.findall(combined_text) if c in AIRPORTS_MAP]
            if len(found_iatas) >= 2:
                origin = found_iatas[0]
                destination = found_iatas[1]

        # A hotel or concert "booking" has no flight details; skip it
        query_parts = [p for p in [airline, flight_number, origin, destination] if p]
        if not query_parts:
            continue
        gflights_url = f"https://www.google.com/travel/flights?q={urllib.parse.quote(' '.join(query_parts))}"

        # Unparsed fields stay None: never fill in another booking's details
        reservations.append({
            "flight_number": flight_number,
            "airline": airline,
            "from": origin,
            "to": destination,
            "departure": None,
            "arrival": None,
            "booking_ref": booking_ref,
            "email_subject": subject,
            "email_date": msg.get("date", ""),
            "google_flights_url": gflights_url,
        })

    return reservations
