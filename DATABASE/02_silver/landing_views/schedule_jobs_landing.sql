-- View silver.schedule_jobs_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.schedule_jobs_landing AS
 SELECT job_id::text COLLATE "C" AS job_id,
    schedule_id,
    created_on
   FROM bronze.schedule_jobs;
