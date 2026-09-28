-- View silver.upload_batches_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.upload_batches_landing AS
 SELECT id,
    type_id,
    created_by,
    created_at,
    user_notified,
    notified_at,
    details::jsonb AS details
   FROM bronze.upload_batches;
