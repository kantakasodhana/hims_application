"""One error format for the whole system (API contract, Ref Standards; NFR-17).

Every error reply has the same 3 fields:
    {"error_code": "PATIENT_NOT_FOUND", "message": "No patient has ID 7.", "field": null}
"""
from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class AppError(Exception):
    """Raise this in service.py when a business rule stops the request.

    Example:
        raise AppError(404, "USER_NOT_FOUND", "No user has ID 7.")
    """

    def __init__(self, status_code: int, error_code: str, message: str, field: str | None = None):
        super().__init__(message)
        self.status_code = status_code
        self.error_code = error_code
        self.message = message
        self.field = field


async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"error_code": exc.error_code, "message": exc.message, "field": exc.field},
    )


async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    """FastAPI checks the request shape (schemas.py). Give its errors the same format."""
    first = exc.errors()[0]
    location = [str(part) for part in first.get("loc", []) if part not in ("body", "query", "path")]
    field = ".".join(location) or None
    if first.get("type") == "missing":
        code, message = "FIELD_REQUIRED", f"{field} is required."
    else:
        code, message = "FIELD_INVALID", f"{field}: {first.get('msg')}"
    return JSONResponse(status_code=422, content={"error_code": code, "message": message, "field": field})
