-- View silver.schedule_labels_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.schedule_labels_landing AS
 SELECT id,
    schedule_id,
    label_id,
    created_on,
    created_by
   FROM bronze.schedule_labels;
