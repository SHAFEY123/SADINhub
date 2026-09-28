-- silver.classify_frequency(p_value double precision, p_prev_value double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_frequency(p_value double precision, p_prev_value double precision)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        59.0,   -- hard_min (was 59.3)
        61.0,   -- hard_max (was 60.5)
        59.3,   -- acceptable_min (was 59.0)
        60.5,   -- acceptable_max (was 61.0)
        0.0,    -- invalid_min (unchanged)
        61.0,   -- invalid_max (unchanged)
        50.0    -- spike_pct (unchanged)
    );
$function$
