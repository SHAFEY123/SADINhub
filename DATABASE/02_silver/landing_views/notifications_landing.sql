-- View silver.notifications_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.notifications_landing AS
 SELECT id,
    notification_group_id,
    contact_id,
    contact_method_id,
    notification_type_id,
    successfully_sent,
    read,
    read_ts,
    "timestamp",
    details::jsonb AS details
   FROM bronze.notifications;
