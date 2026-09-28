-- View silver.upload_batch_items_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.upload_batch_items_landing AS
 SELECT id,
    batch_id,
    status_id,
    original_filename COLLATE "C" AS original_filename,
    created_at,
    details::jsonb AS details
   FROM bronze.upload_batch_items;
