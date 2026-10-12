"""Module C - Consultation: endpoints (URLs)."""
from fastapi import APIRouter

from app.modules.c_consultation import service

router = APIRouter(prefix="/api/v1/consultations", tags=["C - Consultation"])


@router.get("/ping")
def ping():
    """Test endpoint. Delete it when you add real endpoints."""
    return service.ping()
