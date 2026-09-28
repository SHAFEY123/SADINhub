-- View silver.banned_jtis_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.banned_jtis_landing AS
 SELECT id,
    refresh_token_jti,
    user_id,
    created_on
   FROM bronze.banned_jtis;
