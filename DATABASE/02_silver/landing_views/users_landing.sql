-- View silver.users_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.users_landing AS
 SELECT id,
    email::text COLLATE "C" AS email,
    first_name::text COLLATE "C" AS first_name,
    last_name::text COLLATE "C" AS last_name,
    password::text COLLATE "C" AS password,
    role_id,
    active,
    mfa_factor_id,
    created_on,
    facility_id,
    mqtt_account_id,
    avatar::text COLLATE "C" AS avatar,
    preferences::jsonb AS preferences,
    address_id,
    force_mfa
   FROM bronze.users;
