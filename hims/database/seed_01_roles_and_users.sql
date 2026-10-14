-- =====================================================================
-- HIMS start data (seed). Run ONE time, after HIMS_Create_Tables.sql and Creating_indexes.sql.
-- It ADDS ROWS ONLY. It does not change any table. Safe to run again (ON CONFLICT DO NOTHING).
--
-- How to run in Codespaces (terminal):
--   psql "${DATABASE_URL/+psycopg/}" -f hims/database/seed_01_roles_and_users.sql
--
-- After it: give each user a real password with
--   cd hims/backend && python -m scripts.set_password admin
-- The value 'NOT_SET' is not a valid bcrypt hash, so nobody can log in before that.
-- =====================================================================

-- 1. The 7 roles. The CHECK rule on hims_dev.role allows only these names.
INSERT INTO hims_dev.role (role_name) VALUES
    ('Admin'), ('Doctor'), ('Receptionist'), ('Laboratory Technician'),
    ('Billing Clerk'), ('System Administrator'), ('Database Administrator')
ON CONFLICT (role_name) DO NOTHING;

-- 2. The first user. Nobody made this user, so created_by stays empty.
INSERT INTO hims_dev.app_user (username, full_name, password_hash, role_id, must_change_password)
SELECT 'admin', 'System Admin', 'NOT_SET', role_id, TRUE
FROM hims_dev.role WHERE role_name = 'Admin'
ON CONFLICT (username) DO NOTHING;

-- 3. One test user for each role. Made by 'admin'.
INSERT INTO hims_dev.app_user (username, full_name, password_hash, role_id, must_change_password, created_by)
SELECT v.username, v.full_name, 'NOT_SET', r.role_id, TRUE,
       (SELECT app_user_id FROM hims_dev.app_user WHERE username = 'admin')
FROM (VALUES
        ('reception1', 'Test Receptionist',  'Receptionist'),
        ('doctor1',    'Test Doctor',        'Doctor'),
        ('lab1',       'Test Lab Technician','Laboratory Technician'),
        ('billing1',   'Test Billing Clerk', 'Billing Clerk'),
        ('sysadmin1',  'Test System Admin',  'System Administrator'),
        ('dba1',       'Test DB Admin',      'Database Administrator')
     ) AS v(username, full_name, role_name)
JOIN hims_dev.role r ON r.role_name = v.role_name
ON CONFLICT (username) DO NOTHING;

-- 4. Business settings used by other modules (Module F owns system_setting).
INSERT INTO hims_dev.system_setting (setting_key, setting_value, description, created_by)
SELECT 'MAX_DISCOUNT_PERCENT', '10', 'Highest discount allowed on a bill, in percent (FR-E-002)',
       (SELECT app_user_id FROM hims_dev.app_user WHERE username = 'admin')
ON CONFLICT (setting_key) DO NOTHING;

-- Check:
--   SELECT role_name FROM hims_dev.role;          -> 7 rows
--   SELECT username  FROM hims_dev.app_user;      -> 7 rows
