-- silver.classify_power_factor(p_value double precision, p_prev_value double precision, p_spike_pct double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_power_factor(p_value double precision, p_prev_value double precision, p_spike_pct double precision DEFAULT 50.0)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_value IS NULL THEN NULL

        WHEN p_value < -1
          OR p_value > 1
            THEN 'Invalid'

        -- Problematic outranks Anomaly
        WHEN p_value < 0.6
            THEN 'Problematic'

        WHEN p_prev_value IS NOT NULL
         AND p_prev_value <> 0
         AND ABS(p_value - p_prev_value)
             / ABS(p_prev_value) * 100 >= p_spike_pct
            THEN 'Anomaly'

        WHEN p_value < 0.8
            THEN 'Review Required'

        ELSE 'Acceptable'
    END;
$function$
