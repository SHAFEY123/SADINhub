-- bronze.get_working_non_working_days_consume_per_units(working_non_working_hours_timestamps jsonb)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_working_non_working_days_consume_per_units(working_non_working_hours_timestamps jsonb)
 RETURNS TABLE(unit_name text, day_date text, working_hours_consume numeric, non_working_hours_consume numeric, meter_serial_number text, meter_label text, grid_account_number text, multiplication_factor integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    unit_data JSONB[];
    unit_record JSONB;
    unit_meters_data JSONB;
    meter_id UUID;
    _day_data JSONB;
    working_total DECIMAL;
    non_working_total DECIMAL;
    working_consume DECIMAL;
    non_working_consume DECIMAL;
BEGIN
    RAISE NOTICE 'Starting function execution';

    -- Step 1: Retrieve unit data with their energy meters

    SELECT ARRAY_AGG(data) INTO unit_data
    FROM (
        SELECT 
            JSONB_BUILD_OBJECT(
                'unit_name', units.name,
                'energy_meters', ARRAY_AGG(JSON_BUILD_OBJECT('meter_serial_number',energy_meters.meter_sn, 'meter_label', energy_meters.meter_label , 'meter_device_id',energy_meters.device_id ,'grid_account_number',grid_billing_accounts.number,'multiplication_factor',grid_billing_accounts.multiplication_factor))
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

            -- Reset totals for each meter
            working_total := 0;
            non_working_total := 0;

            -- Iterate through each day's time ranges
            FOR _day_data IN SELECT value FROM jsonb_array_elements(working_non_working_hours_timestamps)
            LOOP
                -- RAISE NOTICE 'Processing day: %', _day_data->>'date';

                -- Calculate consumption for working hours (6am - 6pm)
                BEGIN
                    SELECT * INTO working_consume
                    FROM CALC_meter_consume(
                        (_day_data -> '6am - 6pm' ->> 'start')::BIGINT,
                        (_day_data -> '6am - 6pm' ->> 'end')::BIGINT,
                        meter_id,
                        'kWh'
                    );
                EXCEPTION
                    WHEN SQLSTATE '02000' THEN
                        working_consume := -1; -- Handle "no data found" exception
                END;

                -- Calculate consumption for non-working hours (6:01pm - 5:59am)
                BEGIN
                    SELECT * INTO non_working_consume
                    FROM CALC_meter_consume(
                        (_day_data -> '6:01 pm - 5:59 am' ->> 'start')::BIGINT,
                        (_day_data -> '6:01 pm - 5:59 am' ->> 'end')::BIGINT,
                        meter_id,
                        'kWh'
                    );
                EXCEPTION
                    WHEN SQLSTATE '02000' THEN
                        non_working_consume := -1; -- Handle "no data found" exception
                END;

                -- Accumulate consumption values for the current meter
                working_total := working_total + COALESCE(working_consume, 0);
                non_working_total := non_working_total + COALESCE(non_working_consume, 0);

                -- RAISE NOTICE 'Consume values - Working: %, Non-Working: %',
                --     COALESCE(working_consume, 0), COALESCE(non_working_consume, 0);
                
                unit_name := unit_record->>'unit_name';
                day_date := _day_data ->> 'date';
                working_hours_consume := working_consume;
                non_working_hours_consume := non_working_consume;
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
