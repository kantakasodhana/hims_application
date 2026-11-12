"""Module E - Billing: endpoints (URLs)."""
from fastapi import APIRouter

from app.modules.e_billing import service

router = APIRouter(prefix="/api/v1/billing", tags=["E - Billing"])


@router.get("/ping")
def ping():
    """Test endpoint. Delete it when you add real endpoints."""
    return service.ping()

"""Module E - Billing: endpoints (URLs)."""
from typing import Literal

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.current_user import require_roles
from app.database import get_db
from app.modules.e_billing import service
from app.modules.e_billing.schemas import PriceCreate, PriceListOut, PriceOut, PriceUpdate

router = APIRouter(prefix="/api/v1/billing", tags=["E - Billing"])


@router.get("/ping")
def ping():
    """Test endpoint used by the Billing screen. Delete it when the screen has real calls."""
    return service.ping()


@router.post("/price-list", response_model=PriceOut, status_code=201)
def add_price(body: PriceCreate, db: Session = Depends(get_db),
              user: dict = Depends(require_roles("Admin"))):
    """E1a - Add a price."""
    return service.add_price(db, body, user)


@router.patch("/price-list/{price_list_id}", response_model=PriceOut)
def change_price(price_list_id: int, body: PriceUpdate, db: Session = Depends(get_db),
                 user: dict = Depends(require_roles("Admin"))):
    """E1b - Change, deactivate or reactivate a price."""
    return service.change_price(db, price_list_id, body, user)


@router.get("/price-list", response_model=PriceListOut)
def list_prices(service_type: Literal["Consultation", "Lab Test"] | None = None,
                is_active: bool | None = None, db: Session = Depends(get_db),
                user: dict = Depends(require_roles("Admin", "Billing Clerk"))):
    """E2 - List the prices. Both filters are optional."""
    return service.list_prices(db, service_type, is_active)