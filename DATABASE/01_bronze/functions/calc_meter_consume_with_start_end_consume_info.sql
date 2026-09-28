-- bronze.calc_meter_consume_with_start_end_consume_info(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.calc_meter_consume_with_start_end_consume_info(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    telemetry_key_id INTEGER;
    start_reading_value DECIMAL;
    start_reading_timestamp BIGINT;
    end_reading_value DECIMAL;
    end_reading_timestamp BIGINT;
    consume DECIMAL;
BEGIN
    RAISE NOTICE 'Starting function CALC_meter_consume_with_start_end_consume_info execution';
    -- Get telemetry key ID
    SELECT
        * INTO telemetry_key_id
    FROM
        get_telemetries_key_id_by_key_name(telemetry_key);
    
    -- Get start data
    SELECT
        telemetries.dbl,
        telemetries.timestamp
        INTO
        start_reading_value,
        start_reading_timestamp
    FROM
        telemetries
    WHERE
        telemetries.timestamp >= start_timestamp AND
        telemetries.key_id = telemetry_key_id AND
        telemetries.device_id = meter_id AND
        telemetries.timestamp <= end_timestamp
    ORDER BY
        telemetries.timestamp
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'There is no data >= % for device % and key % in telemetries',
            start_timestamp, meter_id, telemetry_key
            USING ERRCODE = '02000';
    END IF;

    -- Get end data
    SELECT
        telemetries.dbl,
        telemetries.timestamp
        INTO
        end_reading_value,
        end_reading_timestamp
    FROM
        telemetries
    WHERE
        telemetries.timestamp <= end_timestamp AND
        telemetries.key_id = telemetry_key_id AND
        telemetries.device_id = meter_id AND
        telemetries.timestamp >= start_timestamp
    ORDER BY
        telemetries.timestamp DESC
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'There is no data <= % for device % and key % in telemetries',
            end_timestamp, meter_id, telemetry_key
            USING ERRCODE = '02000';
    END IF;

    -- Calculate consumption
    consume := end_reading_value - start_reading_value;

    RAISE NOTICE 'FINSH function CALC_meter_consume_with_start_end_consume_info execution';

    RETURN
        JSONB_BUILD_OBJECT(
            'start_reading_value',start_reading_value,
            'start_reading_timestamp',to_char(to_timestamp(start_reading_timestamp / 1000.0), 'DD/MM/YYYY HH24:MI:SS'),
            'end_reading_value',end_reading_value,
            'end_reading_timestamp',to_char(to_timestamp(end_reading_timestamp / 1000.0), 'DD/MM/YYYY HH24:MI:SS'),
            'consume',consume);
END;
$function$
