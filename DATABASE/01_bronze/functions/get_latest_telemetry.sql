-- bronze.get_latest_telemetry(in_device_id uuid, telemetrie_key_name text)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_latest_telemetry(in_device_id uuid, telemetrie_key_name text)
 RETURNS TABLE(result text)
 LANGUAGE plpgsql
AS $function$
DECLARE
telemetrie_key_name_id INTEGER;
telemetrie_key_type TEXT;
latest_telemetrie_row telemetries_latest%rowtype;
BEGIN
    SELECT id INTO telemetrie_key_name_id FROM telemetries_dictionaries WHERE key = telemetrie_key_name;

    -- using json instead jsonb is very bad for reading performance
    SELECT value ->> 'type' INTO telemetrie_key_type
		FROM device, json_array_elements(user_conf->'keys') AS keys_config
    WHERE keys_config->>'name' = telemetrie_key_name AND device.id = in_device_id;

    RETURN QUERY EXECUTE format('
        SELECT
            %s::TEXT 
        FROM 
            telemetries_latest 
        WHERE
            telemetries_latest.key_id = %s
        AND
            telemetries_latest.device_id = %L'
        ,telemetrie_key_type, telemetrie_key_name_id,in_device_id);

END $function$
