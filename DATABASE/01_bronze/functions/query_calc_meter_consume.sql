-- bronze.query_calc_meter_consume(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.query_calc_meter_consume(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text)
 RETURNS double precision
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN CALC_meter_consume(start_timestamp ,end_timestamp ,meter_id ,telemetry_key)::float;
EXCEPTION
    WHEN SQLSTATE '02000' THEN
        RETURN NULL; -- Or 0 if you prefer a default numerical value
END;
$function$
