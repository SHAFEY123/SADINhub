-- View silver.forget_password_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.forget_password_landing AS
 SELECT id,
    user_id,
    active,
    created_on,
    expires_on,
    token::text COLLATE "C" AS token
   FROM bronze.forget_password;
