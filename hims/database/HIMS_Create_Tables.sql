-- =====================================================================
-- HIMS - PostgreSQL schema (tables only, NO data)
-- Source: HIMS_All_Modules_Combined_ER_Model_Revalidated.xlsx (Modules A-F, 38 tables)
-- Target schema: hims_dev
--
-- Conventions
--   * Primary keys:  BIGINT GENERATED ALWAYS AS IDENTITY
--   * Foreign keys:  BIGINT, default NO ACTION (rows are deactivated via is_active, never deleted)
--   * Timestamps:    TIMESTAMPTZ;  money: NUMERIC(12,2)
--   * Audit columns on main tables: created_at, created_by, updated_at, updated_by, is_active
--   * Master lists (role, cancel_reason, diagnosis_code, medicine, procedure_master) carry only is_active
--   * Log tables (*_status_history, patient_mrn_alias, audit_log, backup_log, restore_log,
--     password_reset_token) are append-only and carry their own who/when columns
--   * Calculated values are NOT stored: patient age, bill outstanding balance,
--     bill_line_item line total, payment remaining balance
--   * Safe to re-run: every statement uses IF NOT EXISTS (or a guarded DO block)
--
-- Table order matters for foreign keys:
--   role -> app_user -> department -> (deferred) app_user.department_id FK -> Module A ->
--   Module B -> price_list -> lab_test_catalogue -> Module C -> Module D -> Module E -> rest of Module F
--
-- Bootstrap note: app_user.created_by is nullable so the very first account (which nobody created) can exist.
-- If you load seed rows with explicit IDs later, use INSERT ... OVERRIDING SYSTEM VALUE
-- (the identity columns are GENERATED ALWAYS).
-- =====================================================================

--CREATE SCHEMA IF NOT EXISTS hims_dev;

-- [Module F] Fixed list of job roles; a user account has exactly one (FR-F-005).
CREATE TABLE IF NOT EXISTS hims_dev.role (
    role_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_name VARCHAR(30) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_role_name UNIQUE (role_name),
    CONSTRAINT ck_role_name CHECK (role_name IN ('Admin', 'Doctor', 'Receptionist', 'Laboratory Technician', 'Billing Clerk', 'System Administrator', 'Database Administrator'))
);


-- [Module F] Staff login accounts. Every created_by/updated_by/changed_by/... column in the system points here (FR-F-001, FR-F-005, FR-F-006, NFR-07).
CREATE TABLE IF NOT EXISTS hims_dev.app_user (
    app_user_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100),
    phone VARCHAR(15),
    password_hash VARCHAR(255) NOT NULL,
    role_id BIGINT NOT NULL,
    department_id BIGINT,
    must_change_password BOOLEAN NOT NULL DEFAULT TRUE,
    failed_login_count INTEGER NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_app_user_username UNIQUE (username),
    CONSTRAINT uq_app_user_email UNIQUE (email),
    CONSTRAINT fk_app_user_role_id FOREIGN KEY (role_id) REFERENCES hims_dev.role (role_id),
    CONSTRAINT fk_app_user_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_app_user_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_app_user_failed_login_count CHECK (failed_login_count >= 0),
    CONSTRAINT ck_app_user_username_not_blank CHECK (btrim(username) <> '')
);

-- [Module B] Hospital departments / specialities (FR-B-001).
CREATE TABLE IF NOT EXISTS hims_dev.department (
    department_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_department_name UNIQUE (department_name),
    CONSTRAINT fk_department_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_department_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id)
);

-- app_user <-> department is circular (department.created_by -> app_user, app_user.department_id -> department),
-- so this foreign key is added after both tables exist. The DO block makes it safe to re-run.

ALTER TABLE hims_dev.app_user DROP CONSTRAINT IF EXISTS fk_app_user_department_id;
ALTER TABLE hims_dev.app_user ADD CONSTRAINT fk_app_user_department_id FOREIGN KEY (department_id) REFERENCES hims_dev.department (department_id);


-- [Module A] One permanent internal identity per patient (FR-A-001..A-003, A-008). Age is NOT stored; it is calculated from date_of_birth.
CREATE TABLE IF NOT EXISTS hims_dev.patient (
    patient_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    mrn VARCHAR(20) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    gender VARCHAR(10) NOT NULL,
    date_of_birth DATE NOT NULL,
    blood_group VARCHAR(5),
    address VARCHAR(250),
    phone VARCHAR(15) NOT NULL,
    id_document_type VARCHAR(15),
    id_document_number VARCHAR(20),
    photo_file VARCHAR(255),
    insurer_name VARCHAR(100),
    insurance_policy_number VARCHAR(50),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_patient_mrn UNIQUE (mrn),
    CONSTRAINT fk_patient_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_patient_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_patient_mrn_format CHECK (mrn ~ '^MRN-[0-9]{9}$'),
    CONSTRAINT ck_patient_full_name_not_blank CHECK (btrim(full_name) <> ''),
    CONSTRAINT ck_patient_phone_not_blank CHECK (btrim(phone) <> ''),
    CONSTRAINT ck_patient_blood_group CHECK (blood_group IS NULL OR blood_group IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
    CONSTRAINT ck_patient_id_document_type CHECK (id_document_type IS NULL OR id_document_type IN ('Aadhar', 'Ration Card')),
    CONSTRAINT ck_patient_id_document_pair CHECK (id_document_number IS NULL OR id_document_type IS NOT NULL)
);

-- [Module A] Emergency contact / next of kin (FR-A-006).
CREATE TABLE IF NOT EXISTS hims_dev.patient_contact (
    patient_contact_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    contact_name VARCHAR(100) NOT NULL,
    relationship VARCHAR(30),
    contact_number VARCHAR(15) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_patient_contact_patient_id FOREIGN KEY (patient_id) REFERENCES hims_dev.patient (patient_id),
    CONSTRAINT fk_patient_contact_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_patient_contact_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_patient_contact_name_not_blank CHECK (btrim(contact_name) <> '')
);

-- [Module A] Retired MRNs kept searchable after a duplicate merge (FR-A-002, FR-A-008). Append-only log.
CREATE TABLE IF NOT EXISTS hims_dev.patient_mrn_alias (
    patient_mrn_alias_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    old_mrn VARCHAR(20) NOT NULL,
    merge_reason VARCHAR(200),
    merged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    merged_by BIGINT NOT NULL,
    CONSTRAINT uq_patient_mrn_alias_old_mrn UNIQUE (old_mrn),
    CONSTRAINT fk_patient_mrn_alias_patient_id FOREIGN KEY (patient_id) REFERENCES hims_dev.patient (patient_id),
    CONSTRAINT fk_patient_mrn_alias_merged_by FOREIGN KEY (merged_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_patient_mrn_alias_format CHECK (old_mrn ~ '^MRN-[0-9]{9}$')
);

-- [Module A] Generic change/access trail for the whole system (FR-A-005, FR-A-007). Append-only. entity_name + entity_id is a soft reference, deliberately NOT a foreign key (it points at different tables).
CREATE TABLE IF NOT EXISTS hims_dev.audit_log (
    audit_log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity_name VARCHAR(50) NOT NULL,
    entity_id BIGINT NOT NULL,
    action VARCHAR(30) NOT NULL,
    changed_field VARCHAR(50),
    old_value VARCHAR(255),
    new_value VARCHAR(255),
    performed_by BIGINT NOT NULL,
    performed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_audit_log_performed_by FOREIGN KEY (performed_by) REFERENCES hims_dev.app_user (app_user_id)
);

-- [Module B] Doctors; each belongs to one department and may be linked to a login account (FR-B-001, FR-C-001).
CREATE TABLE IF NOT EXISTS hims_dev.doctor (
    doctor_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doctor_name VARCHAR(100) NOT NULL,
    department_id BIGINT NOT NULL,
    app_user_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_doctor_app_user_id UNIQUE (app_user_id),
    CONSTRAINT fk_doctor_department_id FOREIGN KEY (department_id) REFERENCES hims_dev.department (department_id),
    CONSTRAINT fk_doctor_app_user_id FOREIGN KEY (app_user_id) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_doctor_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_doctor_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id)
);

-- [Module B] A doctor's configured availability window; appointments must fall inside it (FR-B-001).
CREATE TABLE IF NOT EXISTS hims_dev.doctor_slot (
    doctor_slot_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_doctor_slot_doctor_id FOREIGN KEY (doctor_id) REFERENCES hims_dev.doctor (doctor_id),
    CONSTRAINT fk_doctor_slot_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_doctor_slot_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_doctor_slot_window CHECK (end_time > start_time)
);

-- [Module B] Fixed list of appointment cancellation reasons (FR-B-004).
CREATE TABLE IF NOT EXISTS hims_dev.cancel_reason (
    cancel_reason_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reason_text VARCHAR(150) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_cancel_reason_text UNIQUE (reason_text)
);

-- [Module B] Booked appointment (FR-B-002..B-004, B-006). Department is reached via doctor_id.
CREATE TABLE IF NOT EXISTS hims_dev.appointment (
    appointment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_no VARCHAR(20) NOT NULL,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    doctor_slot_id BIGINT NOT NULL,
    appointment_date DATE NOT NULL,
    appointment_time TIME NOT NULL,
    appointment_status VARCHAR(15) NOT NULL DEFAULT 'Booked',
    cancel_reason_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_appointment_no UNIQUE (appointment_no),
    CONSTRAINT fk_appointment_patient_id FOREIGN KEY (patient_id) REFERENCES hims_dev.patient (patient_id),
    CONSTRAINT fk_appointment_doctor_id FOREIGN KEY (doctor_id) REFERENCES hims_dev.doctor (doctor_id),
    CONSTRAINT fk_appointment_doctor_slot_id FOREIGN KEY (doctor_slot_id) REFERENCES hims_dev.doctor_slot (doctor_slot_id),
    CONSTRAINT fk_appointment_cancel_reason_id FOREIGN KEY (cancel_reason_id) REFERENCES hims_dev.cancel_reason (cancel_reason_id),
    CONSTRAINT fk_appointment_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_appointment_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_appointment_status CHECK (appointment_status IN ('Booked', 'Checked-in', 'With Doctor', 'Completed', 'Cancelled', 'No-show')),
    CONSTRAINT ck_appointment_cancel_reason CHECK (cancel_reason_id IS NULL OR appointment_status = 'Cancelled')
);

-- [Module B] Append-only trail of appointment status changes (FR-B-003).
CREATE TABLE IF NOT EXISTS hims_dev.appointment_status_history (
    history_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id BIGINT NOT NULL,
    status VARCHAR(15) NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by BIGINT NOT NULL,
    CONSTRAINT fk_appointment_status_history_appointment_id FOREIGN KEY (appointment_id) REFERENCES hims_dev.appointment (appointment_id),
    CONSTRAINT fk_appointment_status_history_changed_by FOREIGN KEY (changed_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_appointment_history_status CHECK (status IN ('Booked', 'Checked-in', 'With Doctor', 'Completed', 'Cancelled', 'No-show'))
);

-- [Module B] A patient's actual attendance - from a checked-in appointment, or a walk-in/emergency (FR-B-005, B-007).
CREATE TABLE IF NOT EXISTS hims_dev.visit (
    visit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    visit_no VARCHAR(20) NOT NULL,
    patient_id BIGINT NOT NULL,
    appointment_id BIGINT,
    doctor_id BIGINT NOT NULL,
    visit_type VARCHAR(15) NOT NULL,
    visit_datetime TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_visit_no UNIQUE (visit_no),
	CONSTRAINT uq_visit_appointment UNIQUE (appointment_id),
	CONSTRAINT fk_visit_patient_id FOREIGN KEY (patient_id) REFERENCES hims_dev.patient (patient_id),
    CONSTRAINT fk_visit_appointment_id FOREIGN KEY (appointment_id) REFERENCES hims_dev.appointment (appointment_id),
    CONSTRAINT fk_visit_doctor_id FOREIGN KEY (doctor_id) REFERENCES hims_dev.doctor (doctor_id),
    CONSTRAINT fk_visit_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_visit_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_visit_no_format CHECK (visit_no ~ '^VIS-[0-9]{4}-[0-9]{6}$'),
    CONSTRAINT ck_visit_type CHECK (visit_type IN ('Scheduled', 'Walk-in', 'Emergency')),
    CONSTRAINT ck_visit_appointment_rule CHECK ((visit_type = 'Scheduled') = (appointment_id IS NOT NULL))
);


-- [Module E] Master price list for consultation fees and lab tests (FR-E-001). is_active replaces the separate Status field.
CREATE TABLE IF NOT EXISTS hims_dev.price_list (
    price_list_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    service_name VARCHAR(150) NOT NULL,
    service_type VARCHAR(20) NOT NULL,
    department_id BIGINT,
    price NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_price_list_service_name UNIQUE (service_name),
    CONSTRAINT fk_price_list_department_id FOREIGN KEY (department_id) REFERENCES hims_dev.department (department_id),
    CONSTRAINT fk_price_list_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_price_list_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_price_list_service_type CHECK (service_type IN ('Consultation', 'Lab Test')),
    CONSTRAINT ck_price_list_price CHECK (price > 0),
    CONSTRAINT ck_price_list_department_rule CHECK ((service_type = 'Consultation' AND department_id IS NOT NULL) OR (service_type = 'Lab Test' AND department_id IS NULL))
);

-- [Module D] Lab tests with normal range (FR-D-007). The price lives ONLY in price_list.
CREATE TABLE IF NOT EXISTS hims_dev.lab_test_catalogue (
    lab_test_catalogue_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    test_name VARCHAR(150) NOT NULL,
    normal_range VARCHAR(100) NOT NULL,
    price_list_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_lab_test_catalogue_name UNIQUE (test_name),
    CONSTRAINT uq_lab_test_catalogue_price_list UNIQUE (price_list_id),
    CONSTRAINT fk_lab_test_catalogue_price_list_id FOREIGN KEY (price_list_id) REFERENCES hims_dev.price_list (price_list_id),
    CONSTRAINT fk_lab_test_catalogue_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_lab_test_catalogue_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id)
);

-- [Module C] Header record of the doctor's clinical work for one visit.
CREATE TABLE IF NOT EXISTS hims_dev.consultation (
    consultation_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    visit_id BIGINT NOT NULL,
    chief_complaint VARCHAR(255),
    symptoms VARCHAR(500),
    consultation_status VARCHAR(15) NOT NULL DEFAULT 'In Progress',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_consultation_visit UNIQUE (visit_id),
    CONSTRAINT fk_consultation_visit_id FOREIGN KEY (visit_id) REFERENCES hims_dev.visit (visit_id),
    CONSTRAINT fk_consultation_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_consultation_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_consultation_status CHECK (consultation_status IN ('In Progress', 'Completed'))
);

-- [Module C] Standard diagnosis code list (FR-C-002).
CREATE TABLE IF NOT EXISTS hims_dev.diagnosis_code (
    diagnosis_code_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    diagnosis_code VARCHAR(20) NOT NULL,
    diagnosis_name VARCHAR(150) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_diagnosis_code UNIQUE (diagnosis_code)
);

-- [Module C] Diagnoses recorded for a visit; at most one primary per visit (FR-C-002).
CREATE TABLE IF NOT EXISTS hims_dev.diagnosis (
    diagnosis_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    visit_id BIGINT NOT NULL,
    diagnosis_code_id BIGINT NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_diagnosis_visit_id FOREIGN KEY (visit_id) REFERENCES hims_dev.visit (visit_id),
    CONSTRAINT fk_diagnosis_diagnosis_code_id FOREIGN KEY (diagnosis_code_id) REFERENCES hims_dev.diagnosis_code (diagnosis_code_id),
    CONSTRAINT fk_diagnosis_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_diagnosis_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id)
);

-- [Module C] Medicine master list (FR-C-003).
CREATE TABLE IF NOT EXISTS hims_dev.medicine (
    medicine_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    medicine_name VARCHAR(150) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_medicine_name UNIQUE (medicine_name)
);

-- [Module C] Prescription header, one per visit (FR-C-003).
CREATE TABLE IF NOT EXISTS hims_dev.prescription (
    prescription_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    visit_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_prescription_visit UNIQUE (visit_id),
    CONSTRAINT fk_prescription_visit_id FOREIGN KEY (visit_id) REFERENCES hims_dev.visit (visit_id),
    CONSTRAINT fk_prescription_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_prescription_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id)
);

-- [Module C] One prescribed medicine line (FR-C-003).
CREATE TABLE IF NOT EXISTS hims_dev.prescription_item (
    prescription_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    prescription_id BIGINT NOT NULL,
    medicine_id BIGINT NOT NULL,
    dosage VARCHAR(30) NOT NULL,
    frequency VARCHAR(30) NOT NULL,
    duration VARCHAR(30) NOT NULL,
    instructions VARCHAR(200) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_prescription_item_prescription_id FOREIGN KEY (prescription_id) REFERENCES hims_dev.prescription (prescription_id),
    CONSTRAINT fk_prescription_item_medicine_id FOREIGN KEY (medicine_id) REFERENCES hims_dev.medicine (medicine_id),
    CONSTRAINT fk_prescription_item_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_prescription_item_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id)
);

-- [Module C] Medical/surgical procedure master list (FR-C-004).
CREATE TABLE IF NOT EXISTS hims_dev.procedure_master (
    procedure_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    procedure_name VARCHAR(150) NOT NULL,
    procedure_type VARCHAR(15) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_procedure_master_name UNIQUE (procedure_name),
    CONSTRAINT ck_procedure_master_type CHECK (procedure_type IN ('Medical', 'Surgical'))
);

-- [Module C] Procedure recommended for a visit (FR-C-004).
CREATE TABLE IF NOT EXISTS hims_dev.procedure_recommendation (
    procedure_recommendation_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    visit_id BIGINT NOT NULL,
    procedure_id BIGINT NOT NULL,
    urgency_type VARCHAR(15),
    recommendation_status VARCHAR(15),
    remarks VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_procedure_recommendation_visit_id FOREIGN KEY (visit_id) REFERENCES hims_dev.visit (visit_id),
    CONSTRAINT fk_procedure_recommendation_procedure_id FOREIGN KEY (procedure_id) REFERENCES hims_dev.procedure_master (procedure_id),
    CONSTRAINT fk_procedure_recommendation_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_procedure_recommendation_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_procedure_recommendation_urgency CHECK (urgency_type IS NULL OR urgency_type IN ('Elective', 'Emergency'))
);

-- [Module C] Long-term conditions and allergies recorded for a patient (FR-C-005, FR-C-006).
CREATE TABLE IF NOT EXISTS hims_dev.patient_condition (
    patient_condition_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    condition_type VARCHAR(15) NOT NULL,
    condition_name VARCHAR(150) NOT NULL,
    recorded_in_visit_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_patient_condition_patient_id FOREIGN KEY (patient_id) REFERENCES hims_dev.patient (patient_id),
    CONSTRAINT fk_patient_condition_recorded_in_visit_id FOREIGN KEY (recorded_in_visit_id) REFERENCES hims_dev.visit (visit_id),
    CONSTRAINT fk_patient_condition_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_patient_condition_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_patient_condition_type CHECK (condition_type IN ('Chronic Condition', 'Allergy')),
    CONSTRAINT ck_patient_condition_name_not_blank CHECK (btrim(condition_name) <> '')
);

-- [Module C] A doctor's lab-test request (batch) for a visit (FR-C-007).
CREATE TABLE IF NOT EXISTS hims_dev.lab_order (
    lab_order_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    visit_id BIGINT NOT NULL,
    ordered_by BIGINT NOT NULL,
    remarks VARCHAR(200),
    priority VARCHAR(10) NOT NULL DEFAULT 'Routine',
    ordered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_lab_order_visit_id FOREIGN KEY (visit_id) REFERENCES hims_dev.visit (visit_id),
    CONSTRAINT fk_lab_order_ordered_by FOREIGN KEY (ordered_by) REFERENCES hims_dev.doctor (doctor_id),
    CONSTRAINT fk_lab_order_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_lab_order_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_lab_order_priority CHECK (priority IN ('Routine', 'Emergency'))
);

-- [Module C] One ordered test with its own visible lab order number; processed by Module D (FR-C-007, FR-D-002).
CREATE TABLE IF NOT EXISTS hims_dev.lab_order_item (
    lab_order_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lab_order_no VARCHAR(20) NOT NULL,
    lab_order_id BIGINT NOT NULL,
    lab_test_catalogue_id BIGINT NOT NULL,
    item_status VARCHAR(20) NOT NULL DEFAULT 'Ordered',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_lab_order_item_no UNIQUE (lab_order_no),
    CONSTRAINT fk_lab_order_item_lab_order_id FOREIGN KEY (lab_order_id) REFERENCES hims_dev.lab_order (lab_order_id),
    CONSTRAINT fk_lab_order_item_lab_test_catalogue_id FOREIGN KEY (lab_test_catalogue_id) REFERENCES hims_dev.lab_test_catalogue (lab_test_catalogue_id),
    CONSTRAINT fk_lab_order_item_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_lab_order_item_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_lab_order_item_no_format CHECK (lab_order_no ~ '^LAB-[0-9]{4}-[0-9]{6}$'),
    CONSTRAINT ck_lab_order_item_status CHECK (item_status IN ('Ordered', 'Sample Collected', 'Testing In Progress', 'Results Obtained', 'Verification', 'Report Generated', 'Done'))
);

-- [Module D] Append-only trail of lab order item stages (FR-D-002).
CREATE TABLE IF NOT EXISTS hims_dev.lab_status_history (
    lab_status_history_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lab_order_item_id BIGINT NOT NULL,
    previous_status VARCHAR(20),
    new_status VARCHAR(20) NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by BIGINT NOT NULL,
    CONSTRAINT fk_lab_status_history_lab_order_item_id FOREIGN KEY (lab_order_item_id) REFERENCES hims_dev.lab_order_item (lab_order_item_id),
    CONSTRAINT fk_lab_status_history_changed_by FOREIGN KEY (changed_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_lab_history_new_status CHECK (new_status IN ('Ordered', 'Sample Collected', 'Testing In Progress', 'Results Obtained', 'Verification', 'Report Generated', 'Done')),
    CONSTRAINT ck_lab_history_previous_status CHECK (previous_status IS NULL OR previous_status IN ('Ordered', 'Sample Collected', 'Testing In Progress', 'Results Obtained', 'Verification', 'Report Generated', 'Done'))
);

-- [Module D] Recorded, flagged and verified result for one lab order item (FR-D-003..D-005).
CREATE TABLE IF NOT EXISTS hims_dev.lab_result (
    lab_result_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lab_order_item_id BIGINT NOT NULL,
    result_value VARCHAR(100) NOT NULL,
    result_flag VARCHAR(10),
    recorded_by BIGINT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    verified_by BIGINT,
    verified_at TIMESTAMPTZ,
    report_status VARCHAR(15) NOT NULL DEFAULT 'Draft',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_lab_result_item UNIQUE (lab_order_item_id),
    CONSTRAINT fk_lab_result_lab_order_item_id FOREIGN KEY (lab_order_item_id) REFERENCES hims_dev.lab_order_item (lab_order_item_id),
    CONSTRAINT fk_lab_result_recorded_by FOREIGN KEY (recorded_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_lab_result_verified_by FOREIGN KEY (verified_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_lab_result_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_lab_result_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_lab_result_flag CHECK (result_flag IS NULL OR result_flag IN ('Normal', 'High', 'Low')),
    CONSTRAINT ck_lab_result_status CHECK (report_status IN ('Draft', 'Verified')),
    CONSTRAINT ck_lab_result_verified CHECK (report_status <> 'Verified' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL))
);

-- [Module E] One bill per billing event for a visit (FR-E-002, FR-E-003). Outstanding balance is NOT stored.
CREATE TABLE IF NOT EXISTS hims_dev.bill (
    bill_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bill_no VARCHAR(20) NOT NULL,
    visit_id BIGINT NOT NULL,
    patient_id BIGINT NOT NULL,
    discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    final_total NUMERIC(12,2) NOT NULL DEFAULT 0,
    bill_status VARCHAR(15) NOT NULL DEFAULT 'Draft',
    bill_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_bill_no UNIQUE (bill_no),
    CONSTRAINT fk_bill_visit_id FOREIGN KEY (visit_id) REFERENCES hims_dev.visit (visit_id),
    CONSTRAINT fk_bill_patient_id FOREIGN KEY (patient_id) REFERENCES hims_dev.patient (patient_id),
    CONSTRAINT fk_bill_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_bill_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_bill_no_format CHECK (bill_no ~ '^B-[0-9]{8}-[0-9]{4}$'),
    CONSTRAINT ck_bill_discount CHECK (discount_amount >= 0),
    CONSTRAINT ck_bill_final_total CHECK (final_total >= 0),
    CONSTRAINT ck_bill_status CHECK (bill_status IN ('Draft', 'Final', 'Paid', 'Partly Paid', 'Cancelled'))
);

-- [Module E] One chargeable item on a bill, priced from price_list at billing time (FR-E-002). Line total (unit_price x quantity) is NOT stored.
CREATE TABLE IF NOT EXISTS hims_dev.bill_line_item (
    bill_line_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bill_id BIGINT NOT NULL,
    price_list_id BIGINT NOT NULL,
    line_type VARCHAR(20) NOT NULL,
    consultation_id BIGINT,
    lab_order_item_id BIGINT,
    description VARCHAR(150) NOT NULL,
    unit_price NUMERIC(12,2) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_bill_line_item_bill_id FOREIGN KEY (bill_id) REFERENCES hims_dev.bill (bill_id),
    CONSTRAINT fk_bill_line_item_price_list_id FOREIGN KEY (price_list_id) REFERENCES hims_dev.price_list (price_list_id),
    CONSTRAINT fk_bill_line_item_consultation_id FOREIGN KEY (consultation_id) REFERENCES hims_dev.consultation (consultation_id),
    CONSTRAINT fk_bill_line_item_lab_order_item_id FOREIGN KEY (lab_order_item_id) REFERENCES hims_dev.lab_order_item (lab_order_item_id),
    CONSTRAINT fk_bill_line_item_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_bill_line_item_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_bill_line_item_type CHECK (line_type IN ('Consultation', 'Lab Test')),
    CONSTRAINT ck_bill_line_item_source CHECK ((line_type = 'Consultation' AND consultation_id IS NOT NULL AND lab_order_item_id IS NULL) OR (line_type = 'Lab Test' AND lab_order_item_id IS NOT NULL AND consultation_id IS NULL)),
    CONSTRAINT ck_bill_line_item_unit_price CHECK (unit_price >= 0),
    CONSTRAINT ck_bill_line_item_quantity CHECK (quantity > 0)
);

-- [Module E] Append-only trail of bill status changes (FR-E-003).
CREATE TABLE IF NOT EXISTS hims_dev.bill_status_history (
    bill_status_history_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bill_id BIGINT NOT NULL,
    previous_status VARCHAR(15),
    new_status VARCHAR(15) NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by BIGINT NOT NULL,
    CONSTRAINT fk_bill_status_history_bill_id FOREIGN KEY (bill_id) REFERENCES hims_dev.bill (bill_id),
    CONSTRAINT fk_bill_status_history_changed_by FOREIGN KEY (changed_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_bill_history_new_status CHECK (new_status IN ('Draft', 'Final', 'Paid', 'Partly Paid', 'Cancelled')),
    CONSTRAINT ck_bill_history_previous_status CHECK (previous_status IS NULL OR previous_status IN ('Draft', 'Final', 'Paid', 'Partly Paid', 'Cancelled'))
);

-- [Module E] Insurance claim for a bill, one per bill (FR-E-005).
CREATE TABLE IF NOT EXISTS hims_dev.insurance_claim (
    insurance_claim_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bill_id BIGINT NOT NULL,
    insurer_name VARCHAR(100) NOT NULL,
    policy_number VARCHAR(50) NOT NULL,
    claim_amount NUMERIC(12,2) NOT NULL,
    approved_amount NUMERIC(12,2),
    claim_status VARCHAR(20) NOT NULL DEFAULT 'Submitted',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_insurance_claim_bill UNIQUE (bill_id),
    CONSTRAINT uq_insurance_claim_id_bill UNIQUE (insurance_claim_id, bill_id),
    CONSTRAINT fk_insurance_claim_bill_id FOREIGN KEY (bill_id) REFERENCES hims_dev.bill (bill_id),
    CONSTRAINT fk_insurance_claim_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_insurance_claim_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_insurance_claim_amount CHECK (claim_amount > 0),
    CONSTRAINT ck_insurance_claim_approved_amount CHECK (approved_amount IS NULL OR (approved_amount >= 0 AND approved_amount <= claim_amount)),
    CONSTRAINT ck_insurance_claim_status CHECK (claim_status IN ('Submitted', 'Under Review', 'Approved', 'Partially Approved', 'Rejected', 'Settled')),
    CONSTRAINT ck_insurance_claim_approved_set CHECK (claim_status NOT IN ('Approved', 'Partially Approved') OR approved_amount IS NOT NULL)
);

-- [Module E] A payment received against a bill (FR-E-004). Remaining balance is NOT stored.
CREATE TABLE IF NOT EXISTS hims_dev.payment (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bill_id BIGINT NOT NULL,
    amount_paid NUMERIC(12,2) NOT NULL,
    payment_mode VARCHAR(15) NOT NULL,
    reference_number VARCHAR(50),
    insurance_claim_id BIGINT,
    payment_datetime TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    received_by BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_payment_bill_id FOREIGN KEY (bill_id) REFERENCES hims_dev.bill (bill_id),
    CONSTRAINT fk_payment_received_by FOREIGN KEY (received_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_payment_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_payment_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_payment_insurance_claim FOREIGN KEY (insurance_claim_id, bill_id) REFERENCES hims_dev.insurance_claim (insurance_claim_id, bill_id),  -- claim must belong to the same bill
    CONSTRAINT ck_payment_amount CHECK (amount_paid > 0),
    CONSTRAINT ck_payment_mode CHECK (payment_mode IN ('Cash', 'Card', 'UPI', 'Insurance')),
    CONSTRAINT ck_payment_reference CHECK (payment_mode = 'Cash' OR reference_number IS NOT NULL),
    CONSTRAINT ck_payment_insurance_link CHECK ((payment_mode = 'Insurance') = (insurance_claim_id IS NOT NULL))
);

-- [Module E] Money returned against a payment (FR-E-007). The bill is reached via payment_id.
CREATE TABLE IF NOT EXISTS hims_dev.refund (
    refund_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_id BIGINT NOT NULL,
    refund_amount NUMERIC(12,2) NOT NULL,
    refund_reason VARCHAR(200),
    refund_mode VARCHAR(25),
    refund_datetime TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_by BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_refund_payment_id FOREIGN KEY (payment_id) REFERENCES hims_dev.payment (payment_id),
    CONSTRAINT fk_refund_processed_by FOREIGN KEY (processed_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_refund_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_refund_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_refund_amount CHECK (refund_amount > 0),
    CONSTRAINT ck_refund_mode CHECK (refund_mode IS NULL OR refund_mode IN ('Cash', 'Card', 'UPI', 'Original Payment Mode'))
);

-- [Module F] Single-use, time-limited password reset token (FR-F-006). Store the HASH, never the raw token.
CREATE TABLE IF NOT EXISTS hims_dev.password_reset_token (
    password_reset_token_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id BIGINT NOT NULL,
    reset_token VARCHAR(64) NOT NULL,
    reset_method VARCHAR(20) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_password_reset_token UNIQUE (reset_token),
    CONSTRAINT fk_password_reset_token_app_user_id FOREIGN KEY (app_user_id) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_password_reset_method CHECK (reset_method IN ('Self-Service', 'Admin-Assisted')),
    CONSTRAINT ck_password_reset_expiry CHECK (expires_at > created_at)
);

-- [Module F] One row per database backup attempt (FR-F-004).
CREATE TABLE IF NOT EXISTS hims_dev.backup_log (
    backup_log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    backup_schedule VARCHAR(50),
    backup_location VARCHAR(255) NOT NULL,
    backup_file VARCHAR(255),
    status VARCHAR(10) NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    alert_sent BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT ck_backup_log_status CHECK (status IN ('Success', 'Failed')),
    CONSTRAINT ck_backup_log_times CHECK (completed_at IS NULL OR completed_at >= started_at)
);

-- [Module F] One row per database restore (FR-F-007). backup_file_used is deliberately free text, not an FK.
CREATE TABLE IF NOT EXISTS hims_dev.restore_log (
    restore_log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    backup_file_used VARCHAR(255) NOT NULL,
    performed_by BIGINT NOT NULL,
    authorisation_confirmed BOOLEAN NOT NULL,
    reason_for_restore VARCHAR(255) NOT NULL,
    verification_status VARCHAR(15) NOT NULL,
    restored_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_restore_log_performed_by FOREIGN KEY (performed_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT ck_restore_log_authorised CHECK (authorisation_confirmed IS TRUE),
    CONSTRAINT ck_restore_log_verification CHECK (verification_status IN ('Verified', 'Failed'))
);

-- [Module F] Configurable business limits, e.g. MAX_DISCOUNT_PERCENT (FR-E-002). Only Admin changes them.
CREATE TABLE IF NOT EXISTS hims_dev.system_setting (
    system_setting_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    setting_key VARCHAR(50) NOT NULL,
    setting_value VARCHAR(100) NOT NULL,
    description VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    updated_by BIGINT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_system_setting_key UNIQUE (setting_key),
    CONSTRAINT fk_system_setting_created_by FOREIGN KEY (created_by) REFERENCES hims_dev.app_user (app_user_id),
    CONSTRAINT fk_system_setting_updated_by FOREIGN KEY (updated_by) REFERENCES hims_dev.app_user (app_user_id)
);




-- =====================================================================
-- Rules the database CANNOT enforce on its own - keep these in the application layer (or add triggers):
--   1. appointment.appointment_time must fall inside the chosen doctor_slot window (start_time..end_time),
--      and doctor_slot.doctor_id must equal appointment.doctor_id.
--   2. Exactly ONE primary diagnosis per visit (the partial unique index only prevents a second one).
--   3. Status moves must follow the allowed sequences (appointment, lab item, bill, insurance claim);
--      the CHECKs only restrict the set of allowed values, not the order of moves.
--   4. payment.amount_paid must not exceed the bill's outstanding balance; Insurance payments require
--      claim_status IN ('Approved','Partially Approved','Settled') and must not exceed approved_amount.
--   5. refund.refund_amount must not exceed the linked payment's amount_paid.
--   6. bill.discount_amount must be within SYSTEM_SETTING 'MAX_DISCOUNT_PERCENT'.
--   7. lab_test_catalogue.price_list_id must point to a price_list row with service_type = 'Lab Test'.
--   8. Only a user holding the 'Database Administrator' role may create restore_log rows.
--   9. A doctor's lab_order.ordered_by should be the doctor attached to the visit.
-- =====================================================================
