from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
import os
import httpx
import os
import base64
import json

app = FastAPI()

# Allow CORS for Flutter frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Change to frontend domain in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# FTC API credentials
FILTER_EVENTS = "https://ftc-api.firstinspires.org/v2.0/2024/events"
FIND_TEAMS_IN_REGION = "https://ftc-api.firstinspires.org/v2.0/2024/teams"
FTC_USERNAME = os.getenv("FTC_USERNAME")  # Ensure this is set in your environment
FTC_PASSWORD = os.getenv("FTC_PASSWORD")  # Ensure this is set in your environment
FILTER_JSON_PATH = os.path.join(os.path.dirname(__file__), "backend", "filter.json")

@app.get("/")
def read_root():
    return {"message": "Welcome to the FTC API Proxy"}


def process_events(data):
    sorted_data = {
        "Country": ["All"],
        "Province/State": {},
        "Event": {}
    }

    for event in data.get("events", []):
        country = event.get("country", "Unknown")
        state = event.get("stateprov", "Unknown")
        event_name = event.get("name", "Unknown")

        if country not in sorted_data["Country"]:
            sorted_data["Country"].append(country)

        if country not in sorted_data["Province/State"]:
            sorted_data["Province/State"][country] = ["All"]
        if state not in sorted_data["Province/State"][country]:
            sorted_data["Province/State"][country].append(state)

        if state not in sorted_data["Event"]:
            sorted_data["Event"][state] = ["All"]
        if event_name not in sorted_data["Event"][state]:
            sorted_data["Event"][state].append(event_name)

    return sorted_data


@app.get("/events")
async def get_events():
    if not FTC_USERNAME or not FTC_PASSWORD:
        raise HTTPException(status_code=500, detail="FTC credentials are not set")

    auth = f"{FTC_USERNAME}:{FTC_PASSWORD}"
    encoded_auth = base64.b64encode(auth.encode("utf-8")).decode("utf-8")

    headers = {
        "Authorization": f"Basic {encoded_auth}"
    }

    async with httpx.AsyncClient() as client:
        response = await client.get(FILTER_EVENTS, headers=headers)

    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    events_data = response.json()
    sorted_data = process_events(events_data)

    # Ensure the backend directory exists before writing the file
    os.makedirs(os.path.dirname(FILTER_JSON_PATH), exist_ok=True)

    # Save filter.json inside the backend/ directory
    with open(FILTER_JSON_PATH, "w", encoding="utf-8") as json_file:
        json.dump(sorted_data, json_file, indent=4)

    print(f"Saved filter.json at: {FILTER_JSON_PATH}")  # Debugging
    return {"message": "Filtered events data saved successfully", "file": FILTER_JSON_PATH}


@app.get("/filter.json")
async def get_filter_json():
    """Serves the filter.json file"""
    if not os.path.exists(FILTER_JSON_PATH):
        raise HTTPException(status_code=404, detail="filter.json not found")

    return FileResponse(FILTER_JSON_PATH, media_type="application/json")

@app.get("/teams_in_region")
async def get_teams_in_region():
    if not FTC_USERNAME or not FTC_PASSWORD:
        raise HTTPException(status_code=500, detail="FTC credentials are not set")

    auth = f"{FTC_USERNAME}:{FTC_PASSWORD}"
    encoded_auth = base64.b64encode(auth.encode("utf-8")).decode("utf-8")

    headers = {
        "Authorization": f"Basic {encoded_auth}"
    }

    async with httpx.AsyncClient() as client:
        response = await client.get(FIND_TEAMS_IN_REGION, headers=headers)

    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    events_data = response.json()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
