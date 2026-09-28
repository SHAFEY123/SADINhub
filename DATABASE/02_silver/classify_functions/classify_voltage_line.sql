-- silver.classify_voltage_line(p_value double precision, p_prev_value double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_voltage_line(p_value double precision, p_prev_value double precision)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        360.0,
        440.0,
        380.0,
        420.0,
        0.0,
        600.0,
        50.0
    );
$function$
