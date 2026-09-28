-- bronze.get_telemetries_key_id_by_key_name(key_name text)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_telemetries_key_id_by_key_name(key_name text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
	key_id INTEGER;
BEGIN
	select id into key_id from telemetries_dictionaries where key = key_name;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'key % doesnt exist in telemetries_dictionaries', key_name;
    END IF;

    RETURN key_id;
END;
$function$
