-- bronze.get_each_day_consume_per_units(days_timestamps jsonb)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_each_day_consume_per_units(days_timestamps jsonb)
 RETURNS TABLE(unit_name text, day_date text, day_consume numeric, day_start_consume numeric, day_start_consume_timestamp text, day_end_consume numeric, day_end_consume_timestamp text, meter_serial_number text, meter_label text, grid_account_number text, multiplication_factor integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    unit_data JSONB[];
    unit_record JSONB;
    unit_meters_data JSONB;
    meter_id UUID;
    _day_data JSONB;
    _day_consume JSONB;
BEGIN
    RAISE NOTICE 'Starting function get_each_day_consume_per_units execution';

    -- Step 1: Retrieve unit data with their energy meters

    SELECT ARRAY_AGG(data) INTO unit_data
    FROM (
        SELECT 
            JSONB_BUILD_OBJECT(
                'unit_name', units.name,
                'energy_meters', ARRAY_AGG(
                                    JSON_BUILD_OBJECT('meter_serial_number',energy_meters.meter_sn, 'meter_label', energy_meters.meter_label , 'meter_device_id',energy_meters.device_id,
                                        'grid_account_number',grid_billing_accounts.number,'multiplication_factor',grid_billing_accounts.multiplication_factor)
                                        )
            ) AS data
        FROM 
            energy_meters
        JOIN 
            units ON units.id = energy_meters.unit_id
        JOIN 
            grid_billing_accounts ON energy_meters.grid_billing_account_id = grid_billing_accounts.id
        GROUP BY 
            units.name
        ORDER BY 
            units.name
    ) AS subquery;
    -- Handle case where no units are found
    IF unit_data IS NULL THEN
        RAISE NOTICE 'No units found';
        RETURN;
    END IF;

    -- RAISE NOTICE 'Unit data retrieved: %', unit_data;

    -- Iterate through each unit
    FOREACH unit_record IN ARRAY unit_data LOOP
        -- RAISE NOTICE 'Processing unit: %', unit_record->>'unit_name';

        -- Iterate through each meter in the current unit
        FOR unit_meters_data IN SELECT * FROM jsonb_array_elements(unit_record->'energy_meters')
        LOOP
            meter_id := unit_meters_data ->>'meter_device_id';

            -- RAISE NOTICE 'Processing meter: %', meter_id;

            -- Iterate through each day's time ranges
            FOR _day_data IN SELECT value FROM jsonb_array_elements(days_timestamps)
            LOOP
                -- RAISE NOTICE 'Processing day: %', day_data->>'date';

                -- Calculate consumption for working hours (6am - 6pm)
                BEGIN

                    SELECT 
                        * INTO _day_consume
                    FROM
                        CALC_meter_consume_with_start_end_consume_info(
                            (_day_data -> 'day_timestamps' ->> 'start')::BIGINT,
                            (_day_data -> 'day_timestamps' ->> 'end')::BIGINT,
                            meter_id,
                            'kWh'
                        );

                    RAISE NOTICE 'Starting CALC_meter_consume_with_start_end_consume_info(%s,%s,%s,kWh) -> %s',(_day_data -> 'day_timestamps' ->> 'start')::BIGINT ,(_day_data -> 'day_timestamps' ->> 'end')::BIGINT , meter_id , _day_consume;

                EXCEPTION
                    WHEN SQLSTATE '02000' THEN
                        day_consume := -1; -- Handle "no data found" exception
                END;

                unit_name := unit_record->>'unit_name';
                day_date := _day_data ->> 'date';
                -- CALC_meter_consume_with_start_end_consume_info -> JSONB(start_reading_value ,start_reading_timestamp ,end_reading_value ,end_reading_timestamp ,consume)
                day_consume := _day_consume -> 'consume';
                day_start_consume := _day_consume -> 'start_reading_value';
                day_start_consume_timestamp := _day_consume -> 'start_reading_timestamp';
                day_end_consume := _day_consume -> 'end_reading_value';
                day_end_consume_timestamp := _day_consume -> 'end_reading_timestamp';
                meter_serial_number := unit_meters_data ->> 'meter_serial_number';
                meter_label := unit_meters_data ->> 'meter_label';
                grid_account_number := unit_meters_data ->> 'grid_account_number';
                multiplication_factor := unit_meters_data ->> 'multiplication_factor';
            RETURN NEXT;
            END LOOP;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Function execution completed';
    RETURN;
END;
$function$
