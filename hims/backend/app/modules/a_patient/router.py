"""Module A - Patient: endpoints (URLs)."""
from fastapi import APIRouter

from app.modules.a_patient import service

router = APIRouter(prefix="/api/v1/patients", tags=["A - Patient"])


@router.get("/ping")
def ping():
    """Test endpoint. Delete it when you add real endpoints."""
    return service.ping()
