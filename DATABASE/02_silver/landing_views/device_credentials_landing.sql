-- View silver.device_credentials_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.device_credentials_landing AS
 SELECT cred_id::text COLLATE "C" AS cred_id,
    device_id,
    cred_val::text COLLATE "C" AS cred_val,
    cred_type::text COLLATE "C" AS cred_type,
    extra_credentials::text COLLATE "C" AS extra_credentials,
    created_on,
    username::text COLLATE "C" AS username,
    uudid::text COLLATE "C" AS uudid
   FROM bronze.device_credentials;
