"""Module A - Patient: read and write the database tables of this module."""
from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import text


class PatientRepository:
    def __init__(self, db: Session):
        self.db = db

    def get_by_id(self, patient_id: int) -> Optional[Dict[str, Any]]:
        query = text("""
            SELECT id, mrn, first_name, last_name, gender, dob, phone, email, address, aadhar_number, created_at, updated_at
            FROM patients
            WHERE id = :patient_id
        """)
        result = self.db.execute(query, {"patient_id": patient_id}).mappings().first()
        return dict(result) if result else None

    def get_by_mrn(self, mrn: str) -> Optional[Dict[str, Any]]:
        query = text("""
            SELECT id, mrn, first_name, last_name, gender, dob, phone, email, address, aadhar_number, created_at, updated_at
            FROM patients
            WHERE mrn = :mrn
        """)
        result = self.db.execute(query, {"mrn": mrn}).mappings().first()
        return dict(result) if result else None

    def get_by_aadhar(self, aadhar_number: str) -> Optional[Dict[str, Any]]:
        query = text("""
            SELECT id, mrn, first_name, last_name, gender, dob, phone, email, address, aadhar_number, created_at, updated_at
            FROM patients
            WHERE aadhar_number = :aadhar_number
        """)
        result = self.db.execute(query, {"aadhar_number": aadhar_number}).mappings().first()
        return dict(result) if result else None

    def find_possible_duplicate(self, first_name: str, last_name: str, phone: str) -> Optional[Dict[str, Any]]:
        query = text("""
            SELECT id, mrn, first_name, last_name, phone
            FROM patients
            WHERE LOWER(first_name) = LOWER(:first_name)
              AND LOWER(last_name) = LOWER(:last_name)
              AND phone = :phone
            LIMIT 1
        """)
        result = self.db.execute(query, {
            "first_name": first_name,
            "last_name": last_name,
            "phone": phone
        }).mappings().first()
        return dict(result) if result else None

    def get_next_mrn(self) -> str:
        # Generates a unique 9-digit MRN
        query = text("SELECT COALESCE(MAX(id), 0) + 1 AS next_id FROM patients")
        next_id = self.db.execute(query).scalar()
        return f"{100000000 + (next_id % 900000000)}"

    def create(self, patient_data: dict, mrn: str) -> Dict[str, Any]:   
        query = text("""
            INSERT INTO patients (mrn, first_name, last_name, gender, dob, phone, email, address, aadhar_number, created_at, updated_at)
            VALUES (:mrn, :first_name, :last_name, :gender, :dob, :phone, :email, :address, :aadhar_number, NOW(), NOW())
            RETURNING id, mrn, first_name, last_name, gender, dob, phone, email, address, aadhar_number, created_at, updated_at
        """)
        params = {
            "mrn": mrn,
            "first_name": patient_data["first_name"],
            "last_name": patient_data["last_name"],
            "gender": patient_data["gender"],
            "dob": patient_data["dob"],
            "phone": patient_data["phone"],
            "email": patient_data.get("email"),
            "address": patient_data.get("address"),
            "aadhar_number": patient_data.get("aadhar_number")
        }
        result = self.db.execute(query, params).mappings().first()
        self.db.commit()
        return dict(result)
    
if __name__ == "__main__":
    import os
    import sys
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../..")))
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        repo = PatientRepository(db)
        print("Generated MRN:", repo.get_next_mrn())
    finally:
        db.close()
if __name__ == "__main__":
    import os
    import sys
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../..")))
    from app.database import SessionLocal, engine
    from sqlalchemy import text

    db = SessionLocal()
    try:
        # Ensure patients table exists for local test run
        db.execute(text("""
            CREATE TABLE IF NOT EXISTS patients (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                mrn VARCHAR(20) UNIQUE NOT NULL,
                first_name VARCHAR(100) NOT NULL,
                last_name VARCHAR(100) NOT NULL,
                gender VARCHAR(20) NOT NULL,
                dob DATE NOT NULL,
                phone VARCHAR(20) NOT NULL,
                email VARCHAR(255),
                address TEXT,
                aadhar_number VARCHAR(20),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """))
        db.commit()

        repo = PatientRepository(db)
        print("Generated MRN:", repo.get_next_mrn())
    finally:
        db.close()