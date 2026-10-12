"""Module E - Billing: endpoints (URLs)."""
from fastapi import APIRouter

from app.modules.e_billing import service

router = APIRouter(prefix="/api/v1/billing", tags=["E - Billing"])


@router.get("/ping")
def ping():
    """Test endpoint. Delete it when you add real endpoints."""
    return service.ping()
