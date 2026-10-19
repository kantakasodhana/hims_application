from datetime import date, datetime
from typing import Optional
from pydantic import BaseModel, Field


class PatientBase(BaseModel):
    first_name: str = Field(..., min_length=1, max_length=100)
    last_name: str = Field(..., min_length=1, max_length=100)
    gender: str = Field(..., pattern="^(Male|Female|Other)$")
    dob: date
    phone: str = Field(..., min_length=10, max_length=15)
    email: Optional[str] = None
    address: Optional[str] = None
    aadhar_number: Optional[str] = Field(None, min_length=12, max_length=12)


class PatientCreate(PatientBase):
    confirm_duplicate: bool = False


class PatientResponse(PatientBase):
    id: int
    mrn: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class DuplicateWarningResponse(BaseModel):
    warning: str
    message: str
    matched_patient_id: int
    matched_mrn: str