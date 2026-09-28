-- silver.classify_standard(p_value double precision, p_prev_value double precision, p_hard_min double precision, p_hard_max double precision, p_acceptable_min double precision, p_acceptable_max double precision, p_invalid_min double precision, p_invalid_max double precision, p_spike_pct double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_standard(p_value double precision, p_prev_value double precision, p_hard_min double precision, p_hard_max double precision, p_acceptable_min double precision, p_acceptable_max double precision, p_invalid_min double precision DEFAULT NULL::double precision, p_invalid_max double precision DEFAULT NULL::double precision, p_spike_pct double precision DEFAULT 50.0)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_value IS NULL THEN NULL

        -- Invalid physical or sanity range
        WHEN p_invalid_min IS NOT NULL
         AND p_value < p_invalid_min
            THEN 'Invalid'

        WHEN p_invalid_max IS NOT NULL
         AND p_value > p_invalid_max
            THEN 'Invalid'

        -- Hard operational limits
        WHEN p_hard_min IS NOT NULL
         AND p_value < p_hard_min
            THEN 'Critical'

        WHEN p_hard_max IS NOT NULL
         AND p_value > p_hard_max
            THEN 'Critical'

        -- High spike against previous reading
        WHEN p_prev_value IS NOT NULL
         AND p_prev_value <> 0
         AND ABS(p_value - p_prev_value)
             / ABS(p_prev_value) * 100 >= p_spike_pct
            THEN 'Anomaly'

        -- Outside acceptable range but not outside hard limit
        WHEN p_acceptable_min IS NOT NULL
         AND p_value < p_acceptable_min
            THEN 'Review Required'

        WHEN p_acceptable_max IS NOT NULL
         AND p_value > p_acceptable_max
            THEN 'Review Required'

        ELSE 'Acceptable'
    END;
$function$
