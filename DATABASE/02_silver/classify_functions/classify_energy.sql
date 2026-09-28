-- silver.classify_energy(p_value double precision, p_prev_value double precision, p_user_max double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_energy(p_value double precision, p_prev_value double precision, p_user_max double precision DEFAULT NULL::double precision)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_value IS NULL THEN NULL

        WHEN p_value < 0
            THEN 'Invalid'

        WHEN p_user_max IS NOT NULL
         AND p_value > p_user_max
            THEN 'Critical'

        WHEN p_prev_value IS NOT NULL
         AND p_value < p_prev_value
            THEN 'Anomaly'

        ELSE 'Acceptable'
    END;
$function$
