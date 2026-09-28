-- silver.classify_accumulated_energy_v2(value double precision, prev_value double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_accumulated_energy_v2(value double precision, prev_value double precision)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF prev_value IS NULL THEN RETURN 'Acceptable'; END IF;  -- first-ever reading for this meter, nothing to compare
    IF value < prev_value THEN RETURN 'Invalid'; END IF;      -- decrement -- counter went backward
    RETURN 'Acceptable';
END;
$function$
