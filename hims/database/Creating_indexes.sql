
CREATE INDEX IF NOT EXISTS idx_app_user_role_id ON hims_dev.app_user (role_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_patient_aadhar ON hims_dev.patient (id_document_number) WHERE id_document_type = 'Aadhar';  -- Aadhar must be unique; a Ration Card number may repeat across a family
CREATE INDEX IF NOT EXISTS idx_patient_phone ON hims_dev.patient (phone);
CREATE INDEX IF NOT EXISTS idx_patient_name ON hims_dev.patient (LOWER(full_name));
CREATE INDEX IF NOT EXISTS idx_patient_dob ON hims_dev.patient (date_of_birth);
CREATE INDEX IF NOT EXISTS idx_patient_contact_patient_id ON hims_dev.patient_contact (patient_id);
CREATE INDEX IF NOT EXISTS idx_patient_mrn_alias_patient_id ON hims_dev.patient_mrn_alias (patient_id);
CREATE INDEX IF NOT EXISTS idx_patient_mrn_alias_merged_by ON hims_dev.patient_mrn_alias (merged_by);
CREATE INDEX IF NOT EXISTS idx_audit_log_performed_by ON hims_dev.audit_log (performed_by);
CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON hims_dev.audit_log (entity_name, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_performed_at ON hims_dev.audit_log (performed_at);
CREATE INDEX IF NOT EXISTS idx_doctor_department_id ON hims_dev.doctor (department_id);
CREATE INDEX IF NOT EXISTS idx_doctor_slot_doctor_id ON hims_dev.doctor_slot (doctor_id);
CREATE INDEX IF NOT EXISTS idx_appointment_patient_id ON hims_dev.appointment (patient_id);
CREATE INDEX IF NOT EXISTS idx_appointment_doctor_id ON hims_dev.appointment (doctor_id);
CREATE INDEX IF NOT EXISTS idx_appointment_doctor_slot_id ON hims_dev.appointment (doctor_slot_id);
CREATE INDEX IF NOT EXISTS idx_appointment_cancel_reason_id ON hims_dev.appointment (cancel_reason_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_appointment_doctor_time ON hims_dev.appointment (doctor_id, appointment_date, appointment_time) WHERE appointment_status NOT IN ('Cancelled', 'No-show');  -- no double booking (NFR-05)
CREATE INDEX IF NOT EXISTS idx_appointment_date ON hims_dev.appointment (appointment_date);
CREATE INDEX IF NOT EXISTS idx_appointment_status_history_appointment_id ON hims_dev.appointment_status_history (appointment_id);
CREATE INDEX IF NOT EXISTS idx_appointment_status_history_changed_by ON hims_dev.appointment_status_history (changed_by);
CREATE INDEX IF NOT EXISTS idx_visit_patient_id ON hims_dev.visit (patient_id);
CREATE INDEX IF NOT EXISTS idx_visit_doctor_id ON hims_dev.visit (doctor_id);
CREATE INDEX IF NOT EXISTS idx_price_list_department_id ON hims_dev.price_list (department_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_price_list_active_consultation ON hims_dev.price_list (department_id) WHERE service_type = 'Consultation' AND is_active;  -- one active consultation fee per department
CREATE INDEX IF NOT EXISTS idx_diagnosis_visit_id ON hims_dev.diagnosis (visit_id);
CREATE INDEX IF NOT EXISTS idx_diagnosis_diagnosis_code_id ON hims_dev.diagnosis (diagnosis_code_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_diagnosis_one_primary_per_visit ON hims_dev.diagnosis (visit_id) WHERE is_primary AND is_active;  -- at most one primary; 'exactly one' must still be checked by the application
CREATE INDEX IF NOT EXISTS idx_prescription_item_prescription_id ON hims_dev.prescription_item (prescription_id);
CREATE INDEX IF NOT EXISTS idx_prescription_item_medicine_id ON hims_dev.prescription_item (medicine_id);
CREATE INDEX IF NOT EXISTS idx_procedure_recommendation_visit_id ON hims_dev.procedure_recommendation (visit_id);
CREATE INDEX IF NOT EXISTS idx_procedure_recommendation_procedure_id ON hims_dev.procedure_recommendation (procedure_id);
CREATE INDEX IF NOT EXISTS idx_patient_condition_patient_id ON hims_dev.patient_condition (patient_id);
CREATE INDEX IF NOT EXISTS idx_patient_condition_recorded_in_visit_id ON hims_dev.patient_condition (recorded_in_visit_id);
CREATE INDEX IF NOT EXISTS idx_lab_order_visit_id ON hims_dev.lab_order (visit_id);
CREATE INDEX IF NOT EXISTS idx_lab_order_ordered_by ON hims_dev.lab_order (ordered_by);
CREATE INDEX IF NOT EXISTS idx_lab_order_item_lab_order_id ON hims_dev.lab_order_item (lab_order_id);
CREATE INDEX IF NOT EXISTS idx_lab_order_item_lab_test_catalogue_id ON hims_dev.lab_order_item (lab_test_catalogue_id);
CREATE INDEX IF NOT EXISTS idx_lab_status_history_lab_order_item_id ON hims_dev.lab_status_history (lab_order_item_id);
CREATE INDEX IF NOT EXISTS idx_lab_status_history_changed_by ON hims_dev.lab_status_history (changed_by);
CREATE INDEX IF NOT EXISTS idx_lab_result_recorded_by ON hims_dev.lab_result (recorded_by);
CREATE INDEX IF NOT EXISTS idx_lab_result_verified_by ON hims_dev.lab_result (verified_by);
CREATE INDEX IF NOT EXISTS idx_bill_visit_id ON hims_dev.bill (visit_id);
CREATE INDEX IF NOT EXISTS idx_bill_patient_id ON hims_dev.bill (patient_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_bill_one_open_per_visit ON hims_dev.bill (visit_id) WHERE bill_status IN ('Draft', 'Final');  -- only one Draft/Final bill per visit at a time

CREATE INDEX IF NOT EXISTS idx_bill_line_item_bill_id ON hims_dev.bill_line_item (bill_id);
CREATE INDEX IF NOT EXISTS idx_bill_line_item_price_list_id ON hims_dev.bill_line_item (price_list_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_bill_line_item_consultation ON hims_dev.bill_line_item (consultation_id) WHERE is_active;
   CREATE UNIQUE INDEX IF NOT EXISTS uq_bill_line_item_lab_order_item ON hims_dev.bill_line_item (lab_order_item_id) WHERE is_active;

CREATE INDEX IF NOT EXISTS idx_bill_status_history_bill_id ON hims_dev.bill_status_history (bill_id);
CREATE INDEX IF NOT EXISTS idx_bill_status_history_changed_by ON hims_dev.bill_status_history (changed_by);

CREATE INDEX IF NOT EXISTS idx_payment_bill_id ON hims_dev.payment (bill_id);
CREATE INDEX IF NOT EXISTS idx_payment_received_by ON hims_dev.payment (received_by);
CREATE INDEX IF NOT EXISTS idx_payment_insurance_claim_id ON hims_dev.payment (insurance_claim_id);
CREATE INDEX IF NOT EXISTS idx_payment_datetime ON hims_dev.payment (payment_datetime);

CREATE INDEX IF NOT EXISTS idx_refund_payment_id ON hims_dev.refund (payment_id);
CREATE INDEX IF NOT EXISTS idx_refund_processed_by ON hims_dev.refund (processed_by);

CREATE INDEX IF NOT EXISTS idx_password_reset_token_app_user_id ON hims_dev.password_reset_token (app_user_id);

CREATE INDEX IF NOT EXISTS idx_restore_log_performed_by ON hims_dev.restore_log (performed_by);
CREATE INDEX IF NOT EXISTS idx_app_user_department_id ON hims_dev.app_user (department_id);
   CREATE INDEX IF NOT EXISTS idx_patient_id_document_number ON hims_dev.patient (id_document_number);



