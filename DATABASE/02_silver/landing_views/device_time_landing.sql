-- View silver.device_time_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.device_time_landing AS
 SELECT device_id,
    "timestamp",
    online,
        CASE
            WHEN value IS NULL THEN NULL::double precision
            ELSE round(value::numeric, 9)::double precision
        END AS value,
    telemetry_key_name::text COLLATE "C" AS telemetry_key_name,
    on_time,
    off_time,
    run_time
   FROM bronze.device_time;
