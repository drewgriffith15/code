#!/usr/bin/env python3
"""
weather.py - Fetch 7-day forecast from Open-Meteo for Drew's location (Georgia, Zone 8b).
Usage: python weather.py
"""

import sys
from datetime import datetime

import requests

LAT = 33.436
LON = -84.529
TIMEZONE = "America/New_York"


def fetch_forecast():
    url = "https://api.open-meteo.com/v1/forecast"
    params = {
        "latitude": LAT,
        "longitude": LON,
        "daily": [
            "temperature_2m_max",
            "temperature_2m_min",
            "precipitation_sum",
            "precipitation_probability_max",
            "wind_speed_10m_max",
        ],
        "temperature_unit": "fahrenheit",
        "wind_speed_unit": "mph",
        "precipitation_unit": "inch",
        "forecast_days": 7,
        "timezone": TIMEZONE,
    }

    response = requests.get(url, params=params, timeout=10)
    response.raise_for_status()
    return response.json()


def print_forecast(data):
    daily = data.get("daily", {})
    dates = daily.get("time", [])
    highs = daily.get("temperature_2m_max", [])
    lows = daily.get("temperature_2m_min", [])
    precip = daily.get("precipitation_sum", [])
    precip_prob = daily.get("precipitation_probability_max", [])
    wind = daily.get("wind_speed_10m_max", [])

    print(f"Today: {datetime.now().strftime('%A, %B %d, %Y')}")
    print("7-Day Forecast (Zone 8b Georgia):")
    for i, date in enumerate(dates):
        print(
            f"  {date}: High {highs[i]}F / Low {lows[i]}F | "
            f"Rain: {precip[i]}in ({precip_prob[i]}% chance) | "
            f"Wind: {wind[i]}mph"
        )


if __name__ == "__main__":
    data = fetch_forecast()
    print_forecast(data)
