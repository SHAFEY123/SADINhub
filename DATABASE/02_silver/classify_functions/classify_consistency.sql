-- silver.classify_consistency(p_total double precision, p_phase_sum double precision, p_tolerance_pct double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_consistency(p_total double precision, p_phase_sum double precision, p_tolerance_pct double precision DEFAULT 5.0)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_total IS NULL
          OR p_phase_sum IS NULL
            THEN NULL

        WHEN p_phase_sum = 0
            THEN CASE
                WHEN p_total = 0 THEN 'Acceptable'
                ELSE 'Invalid'
            END

        WHEN ABS(p_total - p_phase_sum)
             / ABS(p_phase_sum) * 100 > p_tolerance_pct
            THEN 'Invalid'

        ELSE 'Acceptable'
    END;
$function$
