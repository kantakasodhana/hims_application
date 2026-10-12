"""Module F - Admin: endpoints (URLs)."""
from fastapi import APIRouter

from app.modules.f_admin import service

router = APIRouter(prefix="/api/v1/admin", tags=["F - Admin"])


@router.get("/ping")
def ping():
    """Test endpoint. Delete it when you add real endpoints."""
    return service.ping()
