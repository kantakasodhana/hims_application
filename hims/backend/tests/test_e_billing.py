"""Tests for Module E - price list (E1a, E1b, E2). Run:  cd hims/backend  then  pytest -q

Every test runs inside ONE database transaction that is rolled back at the end,
so no test row stays in the shared database.
"""
import uuid
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import engine, get_db
from app.main import app

URL = "/api/v1/billing/price-list"
ADMIN = {"X-Username": "admin"}
CLERK = {"X-Username": "billing1"}
RECEPTION = {"X-Username": "reception1"}


# ---------- set-up: one transaction per test, rolled back at the end ----------

@pytest.fixture()
def db():
    connection = engine.connect()
    outer = connection.begin()
    session = Session(bind=connection)
    yield session
    session.close()
    outer.rollback()
    connection.close()


@pytest.fixture()
def client(db):
    def _use_test_session():
        yield db

    app.dependency_overrides[get_db] = _use_test_session
    yield TestClient(app)
    app.dependency_overrides.pop(get_db, None)


# ---------- small helpers ----------

def new_name() -> str:
    return f"Test price {uuid.uuid4().hex[:8]}"


def make_department(db) -> int:
    """Insert a department inside the test transaction (rolled back at the end)."""
    admin_id = db.execute(text("SELECT app_user_id FROM hims_dev.app_user WHERE username = 'admin'")).scalar_one()
    return db.execute(
        text("""
            INSERT INTO hims_dev.department (department_name, created_by)
            VALUES (:name, :user_id) RETURNING department_id
        """),
        {"name": f"Test dept {uuid.uuid4().hex[:8]}", "user_id": admin_id},
    ).scalar_one()


def add_price(client, **changes):
    body = {"service_name": new_name(), "service_type": "Lab Test", "price": "250.00"}
    body.update(changes)
    return client.post(URL, json=body, headers=ADMIN)


def audit(db, price_list_id: int) -> list[tuple]:
    rows = db.execute(
        text("""
            SELECT action, changed_field FROM hims_dev.audit_log
            WHERE entity_name = 'price_list' AND entity_id = :id ORDER BY audit_log_id
        """),
        {"id": price_list_id},
    ).all()
    return [(r.action, r.changed_field) for r in rows]


# ---------- E1a: add a price ----------

def test_add_lab_price(client, db):
    reply = add_price(client)
    assert reply.status_code == 201
    body = reply.json()
    assert set(body) == {"price_list_id", "service_name", "service_type", "price", "is_active"}
    assert Decimal(body["price"]) == Decimal("250.00")
    assert body["is_active"] is True
    assert audit(db, body["price_list_id"]) == [("Create", None)]


def test_add_consultation_price(client, db):
    reply = add_price(client, service_type="Consultation", department_id=make_department(db))
    assert reply.status_code == 201
    assert reply.json()["service_type"] == "Consultation"


def test_second_active_consultation_same_department_409(client, db):
    department_id = make_department(db)
    assert add_price(client, service_type="Consultation", department_id=department_id).status_code == 201
    reply = add_price(client, service_type="Consultation", department_id=department_id)
    assert reply.status_code == 409
    assert reply.json()["error_code"] == "DUPLICATE_SERVICE"


def test_price_zero_or_negative_422(client):
    for bad_price in ("0.00", "-5.00"):
        reply = add_price(client, price=bad_price)
        assert reply.status_code == 422
        assert reply.json()["error_code"] == "PRICE_NOT_POSITIVE"


def test_duplicate_name_409(client):
    name = new_name()
    assert add_price(client, service_name=name).status_code == 201
    reply = add_price(client, service_name=name)
    assert reply.status_code == 409
    assert reply.json()["error_code"] == "DUPLICATE_SERVICE"


def test_consultation_needs_department_422(client):
    reply = add_price(client, service_type="Consultation")
    assert reply.status_code == 422
    assert reply.json()["error_code"] == "FIELD_REQUIRED"


def test_lab_test_with_department_422(client, db):
    reply = add_price(client, department_id=make_department(db))
    assert reply.status_code == 422
    assert reply.json()["error_code"] == "FIELD_INVALID"


def test_unknown_department_404(client):
    reply = add_price(client, service_type="Consultation", department_id=999999999)
    assert reply.status_code == 404
    assert reply.json()["error_code"] == "DEPARTMENT_NOT_FOUND"


# ---------- roles ----------

def test_clerk_can_list_but_not_add(client):
    assert client.get(URL, headers=CLERK).status_code == 200
    reply = client.post(URL, json={"service_name": new_name(), "service_type": "Lab Test", "price": "10.00"},
                        headers=CLERK)
    assert reply.status_code == 403
    assert reply.json()["error_code"] == "ROLE_NOT_ALLOWED"


def test_wrong_role_cannot_list(client):
    assert client.get(URL, headers=RECEPTION).status_code == 403


def test_clerk_cannot_change_price(client):
    price_list_id = add_price(client).json()["price_list_id"]
    reply = client.patch(f"{URL}/{price_list_id}", json={"price": "99.00"}, headers=CLERK)
    assert reply.status_code == 403


def test_no_header_401(client):
    reply = client.get(URL)
    assert reply.status_code == 401
    assert reply.json()["error_code"] == "NOT_AUTHENTICATED"


# ---------- E2: list ----------

def test_list_filters(client, db):
    lab_id = add_price(client).json()["price_list_id"]
    consultation_id = add_price(client, service_type="Consultation",
                                department_id=make_department(db)).json()["price_list_id"]

    items = client.get(URL, params={"service_type": "Lab Test"}, headers=ADMIN).json()["items"]
    assert all(item["service_type"] == "Lab Test" for item in items)
    ids = [item["price_list_id"] for item in items]
    assert lab_id in ids and consultation_id not in ids

    client.patch(f"{URL}/{lab_id}", json={"is_active": False}, headers=ADMIN)
    inactive = client.get(URL, params={"is_active": "false"}, headers=ADMIN).json()["items"]
    assert lab_id in [item["price_list_id"] for item in inactive]
    assert all(item["is_active"] is False for item in inactive)


# ---------- E1b: change, deactivate, reactivate ----------

def test_change_price_writes_audit(client, db):
    price_list_id = add_price(client).json()["price_list_id"]
    reply = client.patch(f"{URL}/{price_list_id}", json={"price": "300.00"}, headers=ADMIN)
    assert reply.status_code == 200
    assert Decimal(reply.json()["price"]) == Decimal("300.00")
    assert audit(db, price_list_id) == [("Create", None), ("Update", "price")]


def test_change_price_zero_422(client):
    price_list_id = add_price(client).json()["price_list_id"]
    reply = client.patch(f"{URL}/{price_list_id}", json={"price": "0"}, headers=ADMIN)
    assert reply.status_code == 422
    assert reply.json()["error_code"] == "PRICE_NOT_POSITIVE"


def test_change_unknown_price_404(client):
    reply = client.patch(f"{URL}/999999999", json={"price": "10.00"}, headers=ADMIN)
    assert reply.status_code == 404
    assert reply.json()["error_code"] == "PRICE_NOT_FOUND"


def test_deactivate_and_reactivate_write_audit(client, db):
    price_list_id = add_price(client).json()["price_list_id"]
    off = client.patch(f"{URL}/{price_list_id}", json={"is_active": False}, headers=ADMIN)
    assert off.status_code == 200 and off.json()["is_active"] is False
    on = client.patch(f"{URL}/{price_list_id}", json={"is_active": True}, headers=ADMIN)
    assert on.status_code == 200 and on.json()["is_active"] is True
    assert audit(db, price_list_id)[1:] == [("Deactivate", "is_active"), ("Reactivate", "is_active")]


def test_same_values_change_nothing(client, db):
    price_list_id = add_price(client).json()["price_list_id"]
    reply = client.patch(f"{URL}/{price_list_id}", json={"price": "250.00"}, headers=ADMIN)
    assert reply.status_code == 200
    assert audit(db, price_list_id) == [("Create", None)]


def test_reactivate_blocked_by_other_active_consultation(client, db):
    department_id = make_department(db)
    first = add_price(client, service_type="Consultation", department_id=department_id).json()["price_list_id"]
    client.patch(f"{URL}/{first}", json={"is_active": False}, headers=ADMIN)
    assert add_price(client, service_type="Consultation", department_id=department_id).status_code == 201
    reply = client.patch(f"{URL}/{first}", json={"is_active": True}, headers=ADMIN)
    assert reply.status_code == 409
    assert reply.json()["error_code"] == "DUPLICATE_SERVICE"