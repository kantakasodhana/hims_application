"""Module B - Appointment: endpoints (URLs)."""
from fastapi import APIRouter

from app.modules.b_appointment import service

router = APIRouter(prefix="/api/v1/appointments", tags=["B - Appointment"])


@router.get("/ping")
def ping():
    """Test endpoint. Delete it when you add real endpoints."""
    return service.ping()
