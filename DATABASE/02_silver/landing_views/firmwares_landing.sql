-- View silver.firmwares_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.firmwares_landing AS
 SELECT id,
    filename::text COLLATE "C" AS filename,
    client_id::text COLLATE "C" AS client_id,
    version::text COLLATE "C" AS version,
    created_by,
    created_on
   FROM bronze.firmwares;
