-- silver.worst_status(VARIADIC p_statuses text[])
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.worst_status(VARIADIC p_statuses text[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT status_value
    FROM unnest(p_statuses) AS status_value
    WHERE status_value IS NOT NULL
    ORDER BY silver.status_rank(status_value) DESC
    LIMIT 1;
$function$
