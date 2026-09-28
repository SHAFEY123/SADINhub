-- View silver.attempted_logins_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.attempted_logins_landing AS
 SELECT id,
    user_id,
    ip_address::text COLLATE "C" AS ip_address,
    is_successful,
    details::text COLLATE "C" AS details,
    created_on
   FROM bronze.attempted_logins;
