-- View silver.device_control_labels_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.device_control_labels_landing AS
 SELECT device_control_id,
    label_id,
    created_by,
    created_on
   FROM bronze.device_control_labels;
