-- bronze.get_working_custom_groups_consume_per_units(custom_groups_timestamps jsonb)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_working_custom_groups_consume_per_units(custom_groups_timestamps jsonb)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    unit_data JSONB[];
    unit_record JSONB;
    unit_meters_data JSONB;
    meter_id UUID;
    day_data JSONB;
    group_data RECORD;
    day_groups_data JSONB;
    group_consume DECIMAL;
    day_date TEXT;
    unit_name TEXT;
    meter_serial_number TEXT;
    meter_label TEXT;
    grid_account_number TEXT;
    multiplication_factor DECIMAL;
    result JSONB := '[]'::JSONB;  -- To store final result
BEGIN
    RAISE NOTICE 'Starting function execution';

    -- Step 1: Retrieve unit data with their energy meters
    SELECT ARRAY_AGG(data) INTO unit_data
    FROM (
        SELECT 
            JSONB_BUILD_OBJECT(
                'unit_name', units.name,
                'energy_meters', ARRAY_AGG(
                    JSON_BUILD_OBJECT(
                        'meter_serial_number', energy_meters.meter_sn,
                        'meter_label', energy_meters.meter_label,
                        'meter_device_id', energy_meters.device_id,
                        'grid_account_number', grid_billing_accounts.number,
                        'multiplication_factor', grid_billing_accounts.multiplication_factor
                    )
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
        RETURN result;
    END IF;

    -- Step 2: Iterate through each unit
    FOREACH unit_record IN ARRAY unit_data LOOP

        -- Step 3: Iterate through each meter in the current unit
        FOR unit_meters_data IN SELECT * FROM jsonb_array_elements(unit_record->'energy_meters')
        LOOP
            meter_id := unit_meters_data->>'meter_device_id';

            -- Step 4: Iterate through each day
            FOR day_data IN SELECT value FROM jsonb_array_elements(custom_groups_timestamps)
            LOOP
                -- Initialize empty JSONB object for the day's group data
                day_groups_data := JSONB_BUILD_OBJECT(
                    'unit_name', unit_record->>'unit_name',
                    'meter_serial_number', unit_meters_data->>'meter_serial_number',
                    'meter_label', unit_meters_data->>'meter_label',
                    'grid_account_number', unit_meters_data->>'grid_account_number',
                    'multiplication_factor', unit_meters_data->>'multiplication_factor',
                    'day_date', day_data->>'date'
                );

                RAISE NOTICE 'Processing Day Group Data: %', day_groups_data;

                -- Step 5: Iterate through each group in the day's data
                FOR group_data IN SELECT key, value FROM jsonb_each(day_data) WHERE key != 'date'
                LOOP
                    -- Correct way to access the start and end values for the group
                    BEGIN
                        -- Calculate group consumption
                        SELECT * INTO group_consume
                        FROM CALC_meter_consume(
                            (day_data->group_data.key->>'start_timestamp')::BIGINT,  -- Access start timestamp correctly
                            (day_data->group_data.key->>'end_timestamp')::BIGINT,    -- Access end timestamp correctly
                            meter_id,
                            'kWh'
                        );
                    EXCEPTION
                        WHEN SQLSTATE '02000' THEN
                            group_consume := -1; -- Handle "no data found" exception
                    END;

                    -- Append the group_name and group_consume to the day's JSON object
                    day_groups_data := day_groups_data || JSONB_BUILD_OBJECT(
                        group_data.key, group_consume
                    );
                END LOOP;

                RAISE NOTICE 'Completed Day Group Data: %', day_groups_data;

                -- After processing all groups for the day, append the day data to the result
                result := result || day_groups_data;
            END LOOP;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Function execution completed';

    -- Return the accumulated result
    RETURN result;
END;
$function$
