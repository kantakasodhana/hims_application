"""Tests for the shared core helpers. Run:  cd hims/backend  then  pytest -q"""
from fastapi import Depends
from fastapi.testclient import TestClient
from pydantic import BaseModel

from app.core.current_user import require_roles
from app.core.errors import AppError
from app.main import app


# Two small endpoints that exist only during the tests.
class _Body(BaseModel):
    name: str


@app.post("/_test/shape")
def _shape(body: _Body):
    return body


@app.get("/_test/error")
def _error():
    raise AppError(404, "THING_NOT_FOUND", "No thing has ID 7.", "thing_id")


@app.get("/_test/admin-only")
def _admin_only(user: dict = Depends(require_roles("Admin"))):
    return user


client = TestClient(app)


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_app_error_has_the_team_format():
    reply = client.get("/_test/error")
    assert reply.status_code == 404
    assert reply.json() == {"error_code": "THING_NOT_FOUND", "message": "No thing has ID 7.", "field": "thing_id"}


def test_missing_field_has_the_team_format():
    reply = client.post("/_test/shape", json={})
    assert reply.status_code == 422
    assert reply.json()["error_code"] == "FIELD_REQUIRED"
    assert reply.json()["field"] == "name"


def test_unknown_user_is_401():
    reply = client.get("/_test/admin-only", headers={"X-Username": "nobody"})
    assert reply.status_code == 401
    assert reply.json()["error_code"] == "NOT_AUTHENTICATED"


def test_no_header_is_401():
    reply = client.get("/_test/admin-only")
    assert reply.status_code == 401
    assert reply.json()["error_code"] == "NOT_AUTHENTICATED"
