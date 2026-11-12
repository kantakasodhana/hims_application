"""Module E - Billing: business rules."""


def ping():
    return {"module": "E", "message": "Billing module is working"}
"""Module E - Billing: business rules (price list)."""
from decimal import Decimal

from sqlalchemy.orm import Session

from app.core.audit import write_audit
from app.core.errors import AppError
from app.modules.e_billing import repository
from app.modules.e_billing.schemas import PriceCreate, PriceUpdate


def ping():
    return {"module": "E", "message": "Billing module is working"}


# ---------- small checks ----------

def _clean_name(service_name: str) -> str:
    """Remove spaces at both ends. A blank name is not allowed (FR-E-001 a)."""
    name = service_name.strip()
    if not name:
        raise AppError(422, "FIELD_REQUIRED", "service_name is required.", "service_name")
    return name


def _check_price(price: Decimal) -> None:
    """The price must be more than 0 (FR-E-001 a)."""
    if price <= 0:
        raise AppError(422, "PRICE_NOT_POSITIVE", "The price must be more than 0.", "price")


def _check_department(db: Session, service_type: str, department_id: int | None) -> None:
    """A Consultation price needs an active department. A Lab Test price must have none."""
    if service_type == "Lab Test":
        if department_id is not None:
            raise AppError(422, "FIELD_INVALID", "department_id: a Lab Test price must not have a department.",
                           "department_id")
        return
    if department_id is None:
        raise AppError(422, "FIELD_REQUIRED", "department_id is required for a Consultation price.",
                       "department_id")
    department = repository.get_department(db, department_id)
    if department is None:
        raise AppError(404, "DEPARTMENT_NOT_FOUND", f"No department has ID {department_id}.", "department_id")
    if not department["is_active"]:
        raise AppError(422, "DEPARTMENT_INACTIVE", "The department is Inactive. You cannot use it in new work.",
                       "department_id")


def _check_name_free(db: Session, service_name: str) -> None:
    """Two prices cannot have the same name, active or not (BR-E-01)."""
    if repository.find_by_name(db, service_name):
        raise AppError(409, "DUPLICATE_SERVICE", "A price with this service name exists.", "service_name")


def _check_no_other_active_consultation(db: Session, department_id: int) -> None:
    """Only one active Consultation price for each department (FR-E-002 a)."""
    if repository.find_active_consultation(db, department_id):
        raise AppError(409, "DUPLICATE_SERVICE",
                       "This department already has an active Consultation price.", "department_id")


# ---------- E1a: add a price ----------

def add_price(db: Session, data: PriceCreate, user: dict) -> dict:
    name = _clean_name(data.service_name)
    _check_price(data.price)
    _check_department(db, data.service_type, data.department_id)
    _check_name_free(db, name)
    if data.service_type == "Consultation":
        _check_no_other_active_consultation(db, data.department_id)

    row = repository.insert_price(db, name, data.service_type, data.department_id, data.price,
                                  user["app_user_id"])
    write_audit(db, "price_list", row["price_list_id"], "Create", user["app_user_id"])
    return row


# ---------- E1b: change, deactivate or reactivate a price ----------

def _audit_changes(db: Session, price_list_id: int, old: dict, new: dict, user_id: int) -> None:
    """One audit row for each field that really changed (SM-03 moves 2 and 3)."""
    if new["service_name"] != old["service_name"]:
        write_audit(db, "price_list", price_list_id, "Update", user_id,
                    "service_name", old["service_name"], new["service_name"])
    if new["price"] != old["price"]:
        write_audit(db, "price_list", price_list_id, "Update", user_id, "price", old["price"], new["price"])
    if new["is_active"] != old["is_active"]:
        action = "Reactivate" if new["is_active"] else "Deactivate"
        write_audit(db, "price_list", price_list_id, action, user_id,
                    "is_active", old["is_active"], new["is_active"])


def change_price(db: Session, price_list_id: int, data: PriceUpdate, user: dict) -> dict:
    current = repository.get_price(db, price_list_id)
    if current is None:
        raise AppError(404, "PRICE_NOT_FOUND", f"No price has ID {price_list_id}.", "price_list_id")

    # Only the fields the caller really sent. A value of None means "not sent".
    sent = {k: v for k, v in data.model_dump(exclude_unset=True).items() if v is not None}
    name = _clean_name(sent["service_name"]) if "service_name" in sent else current["service_name"]
    price = sent.get("price", current["price"])
    is_active = sent.get("is_active", current["is_active"])

    _check_price(price)
    if name != current["service_name"]:
        _check_name_free(db, name)
    reactivating = is_active and not current["is_active"]
    if reactivating and current["service_type"] == "Consultation":
        _check_no_other_active_consultation(db, current["department_id"])

    new = {"service_name": name, "price": price, "is_active": is_active}
    if all(new[k] == current[k] for k in new):
        return current  # nothing changed: no save, no audit row

    row = repository.update_price(db, price_list_id, name, price, is_active, user["app_user_id"])
    _audit_changes(db, price_list_id, current, new, user["app_user_id"])
    return row


# ---------- E2: list the prices ----------

def list_prices(db: Session, service_type: str | None, is_active: bool | None) -> dict:
    return {"items": repository.list_prices(db, service_type, is_active)}