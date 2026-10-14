"""Starts the backend. Adds the endpoints of all 6 modules."""
from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError

from app.core.errors import AppError, app_error_handler, validation_error_handler
from app.modules.a_patient import router as a_patient
from app.modules.b_appointment import router as b_appointment
from app.modules.c_consultation import router as c_consultation
from app.modules.d_laboratory import router as d_laboratory
from app.modules.e_billing import router as e_billing
from app.modules.f_admin import router as f_admin

app = FastAPI(title="HIMS API")
app.add_exception_handler(AppError, app_error_handler)
app.add_exception_handler(RequestValidationError, validation_error_handler)

app.include_router(a_patient.router)
app.include_router(b_appointment.router)
app.include_router(c_consultation.router)
app.include_router(d_laboratory.router)
app.include_router(e_billing.router)
app.include_router(f_admin.router)


@app.get("/health")
def health():
    return {"status": "ok"}
