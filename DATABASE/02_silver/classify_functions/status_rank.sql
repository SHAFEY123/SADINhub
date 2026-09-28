-- silver.status_rank(p_status text)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.status_rank(p_status text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_status
        WHEN 'Acceptable'      THEN 1
        WHEN 'Review Required' THEN 2
        WHEN 'Anomaly'         THEN 3
        WHEN 'Problematic'     THEN 4
        WHEN 'Critical'        THEN 5
        WHEN 'Invalid'         THEN 6
        ELSE 0
    END;
$function$
