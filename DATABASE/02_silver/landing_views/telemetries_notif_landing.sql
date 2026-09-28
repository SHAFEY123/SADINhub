-- View silver.telemetries_notif_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.telemetries_notif_landing AS
 SELECT id,
    device_id,
    key_id,
    "timestamp",
    bool,
        CASE
            WHEN dbl IS NULL THEN NULL::double precision
            ELSE round(dbl::numeric, 9)::double precision
        END AS dbl,
    "json"::jsonb AS "json",
    long,
    str::text COLLATE "C" AS str,
    msg::text COLLATE "C" AS msg
   FROM bronze.telemetries_notif;
