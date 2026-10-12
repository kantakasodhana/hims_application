"""Admin (Module F) screen."""
import os

import requests
import streamlit as st

API_URL = os.getenv("API_URL", "http://localhost:8000")

st.title("Admin (Module F)")

if st.button("Test connection"):
    try:
        st.write(requests.get(f"{API_URL}/api/v1/admin/ping", timeout=5).json())
    except requests.RequestException:
        st.error("Backend is not running. Start it first (see README.md).")
