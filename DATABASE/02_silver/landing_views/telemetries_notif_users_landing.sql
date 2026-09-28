-- View silver.telemetries_notif_users_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.telemetries_notif_users_landing AS
 SELECT notif_id,
    user_id,
    read,
    read_ts
   FROM bronze.telemetries_notif_users;
