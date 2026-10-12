"""Module D - Laboratory: endpoints (URLs)."""
from fastapi import APIRouter

from app.modules.d_laboratory import service

router = APIRouter(prefix="/api/v1/lab", tags=["D - Laboratory"])


@router.get("/ping")
def ping():
    """Test endpoint. Delete it when you add real endpoints."""
    return service.ping()
