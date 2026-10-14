"""Who is calling, and may this role use the endpoint?

TEMPORARY VERSION (issue "Set up shared core helpers").
The caller sends the header   X-Username: reception1
Issue "Use the login token everywhere" changes ONLY this file to read the login token.
The other modules do not change.

Use in a router:
    user: dict = Depends(require_roles("Admin"))
    user["app_user_id"], user["username"], user["role_name"]
"""
from fastapi import Depends, Header
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.database import get_db


def get_current_user(x_username: str | None = Header(default=None), db: Session = Depends(get_db)) -> dict:
    if not x_username:
        raise AppError(401, "NOT_AUTHENTICATED", "Send the header X-Username (temporary login).")
    row = db.execute(
        text("""
            SELECT u.app_user_id, u.username, u.full_name, r.role_name
            FROM hims_dev.app_user u
            JOIN hims_dev.role r ON r.role_id = u.role_id
            WHERE u.username = :username AND u.is_active
        """),
        {"username": x_username},
    ).mappings().first()
    if row is None:
        raise AppError(401, "NOT_AUTHENTICATED", "Unknown or inactive user.")
    return dict(row)


def require_roles(*allowed_roles: str):
    """Give 403 ROLE_NOT_ALLOWED when the caller's role is not in allowed_roles."""

    def checker(user: dict = Depends(get_current_user)) -> dict:
        if user["role_name"] not in allowed_roles:
            raise AppError(403, "ROLE_NOT_ALLOWED", f"The role {user['role_name']} cannot do this.")
        return user

    return checker
