from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
import os
import httpx
import os
import base64
import json
from dotenv import load_dotenv

load_dotenv()
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
FTC_API_BASE = "https://ftc-api.firstinspires.org/v2.0/2024"
FTC_SCOUT_API_BASE = "https://api.ftcscout.org/rest/v1/teams"
FTC_USERNAME = os.getenv("FTC_USERNAME")
FTC_PASSWORD = os.getenv("FTC_PASSWORD")

if not FTC_USERNAME or not FTC_PASSWORD:
    raise ValueError("FTC API credentials are missing. Ensure they are set in the .env file.")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FILTER_JSON_PATH = os.path.join(BASE_DIR, "filter.json")
TEAM_DATA_JSON_PATH = os.path.join(BASE_DIR, "team_data.json")

def get_auth_header():
    if not FTC_USERNAME or not FTC_PASSWORD:
        raise HTTPException(status_code=500, detail="FTC credentials are not set")

    auth = f"{FTC_USERNAME}:{FTC_PASSWORD}"
    encoded_auth = base64.b64encode(auth.encode("utf-8")).decode("utf-8")
    return {"Authorization": f"Basic {encoded_auth}"}


@app.get("/")
def read_root():
    return {"message": "Welcome to the FTC API Proxy"}


@app.get("/events")
async def get_events():
    """Fetches all FTC events and structures them."""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{FTC_API_BASE}/events", headers=get_auth_header())

    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    events_data = response.json()
    sorted_data = process_events(events_data)

    os.makedirs(os.path.dirname(FILTER_JSON_PATH), exist_ok=True)

    with open(FILTER_JSON_PATH, "w", encoding="utf-8") as json_file:
        json.dump(sorted_data, json_file, indent=4)

    return {"message": "Filtered events data saved successfully", "file": FILTER_JSON_PATH}

@app.get("/filter.json")
async def get_filter_json():
    """Serves the filter.json file"""
    if not os.path.exists(FILTER_JSON_PATH):
        raise HTTPException(status_code=404, detail="filter.json not found")
    return FileResponse(FILTER_JSON_PATH, media_type="application/json")

@app.get("/teams")
async def get_teams(event_name: str):
    """Fetches teams at a specific event and their competition statistics."""

    # Get event code from event name
    event_code = await get_event_code(event_name)
    if not event_code:
        raise HTTPException(status_code=404, detail="Event not found")

    # Fetch teams from FTC API
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{FTC_API_BASE}/teams?eventCode={event_code}", headers=get_auth_header())

    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    teams_data = response.json().get("teams", [])
    if not teams_data:
        raise HTTPException(status_code=404, detail="No teams found for this event")

    # Fetch stats for each team
    processed_teams = []
    for team in teams_data:
        team_number = team.get("teamNumber")
        team_name = team.get("nameShort", "Unknown")

        # Fetch competition stats
        team_stats = await get_team_post_comp_stats(team_number, team_name)

        if team_stats:  # Only add teams that have stats available
            processed_teams.extend(team_stats)


    os.makedirs(os.path.dirname(TEAM_DATA_JSON_PATH), exist_ok=True)

    with open(TEAM_DATA_JSON_PATH, "w", encoding="utf-8") as json_file:
        json.dump(processed_teams, json_file, indent=4)


    return processed_teams

@app.get("/team_stats")
async def get_team_stats(event_name: str):
    """Fetches post-competition stats for all teams in an event"""
    event_code = await get_event_code(event_name)
    if not event_code:
        raise HTTPException(status_code=404, detail="Event not found")

    async with httpx.AsyncClient() as client:
        response = await client.get(f"{FTC_API_BASE}/teams?eventCode={event_code}", headers=get_auth_header())

    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    teams = response.json().get("teams", [])
    if not teams:
        raise HTTPException(status_code=404, detail="No teams found for this event")

    all_team_stats = []
    for team in teams:
        team_number = team.get("teamNumber")
        team_name = team.get("nameShort", "Unknown")
        stats = await get_team_post_comp_stats(team_number, team_name)
        if stats:
            all_team_stats.extend(stats)

    # Ensure the response is JSON structured correctly
    return {"event_code": event_code, "teams": sorted(all_team_stats, key=lambda x: x['alliance'], reverse=True)}
async def get_event_code(event_name):
    """Fetch event code by name"""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{FTC_API_BASE}/events", headers=get_auth_header())

    if response.status_code == 200:
        events = response.json().get("events", [])
        for event in events:
            if event_name.lower() in event.get("name", "").lower():
                return event.get("code")
    return None
async def get_team_post_comp_stats(team_number, team_name):
    """Fetch team post-competition statistics."""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{FTC_SCOUT_API_BASE}/{team_number}/events/2024")

    if response.status_code != 200:
        return None

    stats_list = response.json()
    all_stats = []

    for stats in stats_list:
        if stats.get('stats'):
            auton_sample = round(float(stats['stats']['avg'].get('autoSamplePoints', 0)), 2)
            auton_specimen = round(float(stats['stats']['avg'].get('autoSpecimenPoints', 0)), 2)
            teleop_sample = round(float(stats['stats']['avg'].get('dcSamplePoints', 0)), 2)
            teleop_specimen = round(float(stats['stats']['avg'].get('dcSpecimenPoints', 0)), 2)
            endgame_parking = round(float(stats['stats']['avg'].get('dcParkPoints', 0)), 2)

            # Determine bot type
            tot_sample = auton_sample * 2 + teleop_sample + endgame_parking
            tot_specimen = auton_specimen * 2 + teleop_specimen + endgame_parking
            bot_type = "specimen" if tot_specimen > tot_sample else "sample"

            team_stats = {
                "teamNumber": team_number,
                "teamName": team_name,
                "botType": bot_type,
                "autonSample": auton_sample,
                "autonSpecimen": auton_specimen,
                "teleopSample": teleop_sample,
                "teleopSpecimen": teleop_specimen,
                "endgameParking": endgame_parking
            }

            all_stats.append(team_stats)

    return all_stats if all_stats else None
def process_events(data):
    """Processes and categorizes events"""
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

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
