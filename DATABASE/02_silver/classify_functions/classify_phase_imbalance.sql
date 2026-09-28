-- silver.classify_phase_imbalance(p_imbalance_pct double precision, p_evaluation_status text, p_problematic_threshold_pct double precision, p_critical_threshold_pct double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_phase_imbalance(p_imbalance_pct double precision, p_evaluation_status text, p_problematic_threshold_pct double precision DEFAULT 5.0, p_critical_threshold_pct double precision DEFAULT 5.0)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_imbalance_pct IS NULL
          OR p_evaluation_status IS NULL
            THEN NULL

        WHEN UPPER(p_evaluation_status) = 'OUTSIDE_ACCEPTABLE'
         AND p_imbalance_pct > p_critical_threshold_pct
            THEN 'Critical'

        WHEN UPPER(p_evaluation_status) = 'WITHIN_ACCEPTABLE'
         AND p_imbalance_pct > p_problematic_threshold_pct
            THEN 'Problematic'

        -- Compatibility with previous calls using EVALUATED
        WHEN UPPER(p_evaluation_status) = 'EVALUATED'
         AND p_imbalance_pct > p_critical_threshold_pct
            THEN 'Critical'

        WHEN UPPER(p_evaluation_status) = 'EVALUATED'
         AND p_imbalance_pct > p_problematic_threshold_pct
            THEN 'Problematic'

        ELSE 'Acceptable'
    END;
$function$
