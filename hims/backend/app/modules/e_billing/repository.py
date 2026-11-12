"""Module E - Billing: read and write the database tables of this module."""
"""Module E - Billing: read and write the database tables of this module (price list).

Only SQL lives here. No business rules - those are in service.py.
Always use named parameters (:name). Never put user data into the SQL text.
"""
from decimal import Decimal

from sqlalchemy import text
from sqlalchemy.orm import Session


def get_department(db: Session, department_id: int) -> dict | None:
    """Read one department (Module B owns this table: SELECT only)."""
    row = db.execute(
        text("SELECT department_id, is_active FROM hims_dev.department WHERE department_id = :department_id"),
        {"department_id": department_id},
    ).mappings().first()
    return dict(row) if row else None


def get_price(db: Session, price_list_id: int) -> dict | None:
    """Read one price by its ID."""
    row = db.execute(
        text("""
            SELECT price_list_id, service_name, service_type, department_id, price, is_active
            FROM hims_dev.price_list
            WHERE price_list_id = :price_list_id
        """),
        {"price_list_id": price_list_id},
    ).mappings().first()
    return dict(row) if row else None


def find_by_name(db: Session, service_name: str) -> dict | None:
    """Find a price by its exact service name (active or inactive)."""
    row = db.execute(
        text("""
            SELECT price_list_id, service_name
            FROM hims_dev.price_list
            WHERE service_name = :service_name
        """),
        {"service_name": service_name},
    ).mappings().first()
    return dict(row) if row else None


def find_active_consultation(db: Session, department_id: int) -> dict | None:
    """Find the active Consultation price of a department, if there is one."""
    row = db.execute(
        text("""
            SELECT price_list_id, service_name
            FROM hims_dev.price_list
            WHERE service_type = 'Consultation'
              AND department_id = :department_id
              AND is_active
        """),
        {"department_id": department_id},
    ).mappings().first()
    return dict(row) if row else None


def insert_price(db: Session, service_name: str, service_type: str, department_id: int | None,
                 price: Decimal, user_id: int) -> dict:
    """Insert one price and return the new row. The ID is made by the database."""
    row = db.execute(
        text("""
            INSERT INTO hims_dev.price_list
                (service_name, service_type, department_id, price, created_by)
            VALUES (:service_name, :service_type, :department_id, :price, :user_id)
            RETURNING price_list_id, service_name, service_type, department_id, price, is_active
        """),
        {
            "service_name": service_name,
            "service_type": service_type,
            "department_id": department_id,
            "price": price,
            "user_id": user_id,
        },
    ).mappings().first()
    return dict(row)


def update_price(db: Session, price_list_id: int, service_name: str | None, price: Decimal | None,
                 is_active: bool | None, user_id: int) -> dict:
    """Change a price. A value of None means 'keep the old value' (COALESCE)."""
    row = db.execute(
        text("""
            UPDATE hims_dev.price_list
            SET service_name = COALESCE(:service_name, service_name),
                price        = COALESCE(:price, price),
                is_active    = COALESCE(:is_active, is_active),
                updated_at   = CURRENT_TIMESTAMP,
                updated_by   = :user_id
            WHERE price_list_id = :price_list_id
            RETURNING price_list_id, service_name, service_type, department_id, price, is_active
        """),
        {
            "price_list_id": price_list_id,
            "service_name": service_name,
            "price": price,
            "is_active": is_active,
            "user_id": user_id,
        },
    ).mappings().first()
    return dict(row)


def list_prices(db: Session, service_type: str | None, is_active: bool | None) -> list[dict]:
    """List the prices. A filter that is None is ignored."""
    rows = db.execute(
        text("""
            SELECT price_list_id, service_name, service_type, department_id, price, is_active
            FROM hims_dev.price_list
            WHERE (CAST(:service_type AS VARCHAR) IS NULL OR service_type = :service_type)
              AND (CAST(:is_active AS BOOLEAN) IS NULL OR is_active = :is_active)
            ORDER BY price_list_id
        """),
        {"service_type": service_type, "is_active": is_active},
    ).mappings().all()
    return [dict(r) for r in rows]