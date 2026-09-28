-- bronze.calc_meter_consume(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.calc_meter_consume(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    telemetry_key_id INTEGER;
    start_data DECIMAL;
    end_data DECIMAL;
    consume DECIMAL;
BEGIN
    -- Get telemetry key ID
    SELECT * INTO telemetry_key_id
    FROM get_telemetries_key_id_by_key_name(telemetry_key);
    
    -- Get start data
    SELECT 
        telemetries.dbl INTO start_data
    FROM 
        telemetries
    WHERE 
        "timestamp" >= start_timestamp
        AND key_id = telemetry_key_id
        AND device_id = meter_id
        AND "timestamp" <= end_timestamp
    ORDER BY "timestamp"
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'There is no data >= % for device % and key % in telemetries',
            start_timestamp, meter_id, telemetry_key
            USING ERRCODE = '02000';
            
    END IF;

    -- Get end data
    SELECT
        telemetries.dbl INTO end_data
    FROM
        telemetries
    WHERE
        "timestamp" <= end_timestamp
        AND key_id = telemetry_key_id
        AND device_id = meter_id
        AND "timestamp" >= start_timestamp
    ORDER BY "timestamp" DESC
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'There is no data <= % for device % and key % in telemetries',
            end_timestamp, meter_id, telemetry_key
            USING ERRCODE = '02000';
    END IF;

    -- Calculate consumption
    consume := end_data - start_data;

    RETURN consume;
END;
$function$
