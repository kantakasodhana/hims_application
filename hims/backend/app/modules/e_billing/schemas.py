"""Module E - Billing: the shape of the data going in and out (price list)."""
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field


class PriceCreate(BaseModel):
    """Body of E1a - POST /price-list. Fields with no default are required."""
    service_name: str = Field(min_length=1, max_length=150)
    service_type: Literal["Consultation", "Lab Test"]
    department_id: int | None = None
    price: Decimal = Field(max_digits=12, decimal_places=2)


class PriceUpdate(BaseModel):
    """Body of E1b - PATCH /price-list/{id}. Every field is optional: send only what changes."""
    service_name: str | None = Field(default=None, min_length=1, max_length=150)
    price: Decimal | None = Field(default=None, max_digits=12, decimal_places=2)
    is_active: bool | None = None


class PriceOut(BaseModel):
    """One price in a reply (E1a, E1b and each item of E2)."""
    price_list_id: int
    service_name: str
    service_type: str
    price: Decimal
    is_active: bool


class PriceListOut(BaseModel):
    """Reply of E2 - GET /price-list."""
    items: list[PriceOut]