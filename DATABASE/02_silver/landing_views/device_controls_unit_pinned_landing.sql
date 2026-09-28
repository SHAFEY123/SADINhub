-- View silver.device_controls_unit_pinned_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.device_controls_unit_pinned_landing AS
 SELECT id,
    user_id,
    unit_id,
    pinned,
    visible
   FROM bronze.device_controls_unit_pinned;
