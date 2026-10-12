"""Starts the frontend. Shows the home page and the menu of pages."""
import os

import requests
import streamlit as st
from dotenv import load_dotenv

load_dotenv()
API_URL = os.getenv("API_URL", "http://localhost:8000")

st.title("HIMS")
st.write("Use the menu on the left to open a page.")

try:
    reply = requests.get(f"{API_URL}/health", timeout=5).json()
    st.success(f"Backend is running: {reply}")
except requests.RequestException:
    st.error("Backend is not running. Start it first (see README.md).")
