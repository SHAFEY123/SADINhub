-- bronze.get_meters_consumption_in_range(meter_ids uuid[], input_start_timestamp bigint, input_end_timestamp bigint)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_meters_consumption_in_range(meter_ids uuid[], input_start_timestamp bigint, input_end_timestamp bigint)
 RETURNS TABLE(meter_id uuid, consumption double precision, cost_in_sar double precision, vat_cost double precision, service_class_fee double precision, start_date bigint, end_date bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
	meter_id UUID;
	telemetry_key_id INTEGER;
	current_ts TIMESTAMP;
	_device_id UUID;
	cycle_interval INTERVAL;
	cycle_start_date TIMESTAMP;
	cycle_start_date_in_millisecond BIGINT;
	cycle_end_date TIMESTAMP;
	cycle_end_date_in_millisecond BIGINT;
	continue_loop BOOLEAN := TRUE;
	consumption double precision := 0;
	cost_in_sar double precision := 0;
	grid_billing_acount uuid;
	grid_billing_acount_type uuid;
	total_grid_consumption_in_cycle double precision;
	service_class_fee double precision;
	reading_start_time BIGINT;
	reading_end_time BIGINT;
	consumption_slab_record RECORD; 
	grid_consumption_in_slab double precision;
	service_fee double precision;
	reading_duration INTERVAL;
BEGIN
	CREATE TEMPORARY TABLE temp_table (meter_id UUID, consumption double precision, cost_in_sar double precision, VAT_cost double precision, service_class_fee double precision, start_date BIGINT, end_date BIGINT);

	-- Used to check last cycle to calculate for 
	SELECT CURRENT_TIMESTAMP INTO current_ts;
	
	-- Get key_id for kWh, not hardcoded because previously it caused issues.
	SELECT id INTO telemetry_key_id FROM telemetries_dictionaries WHERE key = 'kWh';

	-- Loop over each provided ID
	FOREACH meter_id IN ARRAY meter_ids LOOP

		-- Fetch general information about the meter and its grid
		SELECT 
			em.device_id,
			days || ' days', 
			start_period::timestamp,
			grid_billing_account_id,
			gba.type_id,
			gba_sc.fee 
		INTO
			_device_id,
			cycle_interval,
			cycle_start_date,
			grid_billing_acount, 
			grid_billing_acount_type,
			service_class_fee
		FROM 
			energy_meters em
		JOIN
			grid_billing_accounts gba ON gba.id = em.grid_billing_account_id 
		JOIN 
			grid_billing_accounts_service_classes gba_sc ON gba_sc.id = gba.service_class_id
		WHERE 
			em.id = meter_id; 

		-- Avoid infinite loop if device is not found
		IF cycle_start_date IS NULL THEN
			CONTINUE;
		END IF;

		-- Set start date to closest billing period to avoid unnecessary calculations  
		WHILE continue_loop LOOP
			IF input_start_timestamp > (EXTRACT(EPOCH FROM ((cycle_start_date + cycle_interval - INTERVAL '1 second') AT TIME ZONE 'Asia/Riyadh'))::bigint * 1000) THEN
				cycle_start_date := cycle_start_date + cycle_interval;
			ELSE
				continue_loop := FALSE;
			END IF;
		END LOOP;
		continue_loop := TRUE;
	
		-- Calculate the end date of the first period
		cycle_end_date := cycle_start_date + cycle_interval - INTERVAL '1 second';

		-- Loop over each period
		WHILE continue_loop LOOP

			-- Next cycle will be in the future 
			IF cycle_start_date + cycle_interval > current_ts THEN
				continue_loop := false;
			END IF;
			
			-- Only added for better readability 
			cycle_start_date_in_millisecond := EXTRACT(EPOCH FROM ((cycle_start_date) AT TIME ZONE 'Asia/Riyadh'))::bigint * 1000;
			cycle_end_date_in_millisecond   := EXTRACT(EPOCH FROM ((cycle_end_date)   AT TIME ZONE 'Asia/Riyadh'))::bigint * 1000;
			
			-- Set time to begin reading for current cycle
			IF input_start_timestamp > cycle_start_date_in_millisecond THEN 
				reading_start_time := input_start_timestamp;
			ELSE
				reading_start_time := cycle_start_date_in_millisecond;
			END IF;

			
			-- Set time to end reading for current cycle
			IF cycle_end_date_in_millisecond >= input_end_timestamp THEN 
				reading_end_time := input_end_timestamp;
				continue_loop := false;
			ELSE
				reading_end_time := cycle_end_date_in_millisecond;
			END IF;
	
			-- Get total consume of grid
			SELECT 
				SUM(COALESCE(ROUND((telemetry_data.end_consume - telemetry_data.start_consume)::numeric, 2)::float, 0))
			INTO
				total_grid_consumption_in_cycle
			FROM device d
			JOIN energy_meters em ON em.device_id = d.id
			JOIN grid_billing_accounts gba ON gba.id = em.grid_billing_account_id
			LEFT JOIN LATERAL (
					SELECT 
						start_query.start_consume AS start_consume,
						end_query.end_consume AS end_consume
					FROM 
						(
						SELECT 
							telemetries.dbl AS start_consume
						FROM 
							telemetries 
						WHERE
							telemetries.device_id = d.id AND
							telemetries.timestamp  >= cycle_start_date_in_millisecond  AND
							telemetries.timestamp <= cycle_end_date_in_millisecond AND
							telemetries.key_id = telemetry_key_id
						ORDER BY telemetries.timestamp ASC
						LIMIT 1
						) AS start_query
					JOIN LATERAL
						(
						SELECT 
							telemetries.dbl AS end_consume
						FROM 
							telemetries 
						WHERE
							telemetries.device_id = d.id AND
							telemetries.timestamp >= cycle_start_date_in_millisecond  AND
							telemetries.timestamp <= cycle_end_date_in_millisecond AND
							telemetries.key_id = telemetry_key_id
						ORDER BY telemetries.timestamp DESC
						LIMIT 1
						) AS end_query ON TRUE
				) AS telemetry_data ON TRUE
			WHERE gba.id = grid_billing_acount
			GROUP BY gba.id;


			SELECT 
				COALESCE(ROUND((telemetry_data.end_consume - telemetry_data.start_consume)::numeric, 2)::float, 0)
			INTO 
				consumption
			FROM device d
			LEFT JOIN LATERAL (
					SELECT 
						start_query.start_consume AS start_consume,
						end_query.end_consume AS end_consume
					FROM 
						(
						SELECT 
							telemetries.dbl AS start_consume
						FROM 
							telemetries 
						WHERE
							telemetries.device_id = d.id AND
							telemetries.timestamp  >= reading_start_time AND
							telemetries.timestamp <= reading_end_time AND
							telemetries.key_id = telemetry_key_id
						ORDER BY telemetries.timestamp ASC
						LIMIT 1
						) AS start_query
					JOIN LATERAL
						(
						SELECT 
							telemetries.dbl AS end_consume
						FROM 
							telemetries 
						WHERE
							telemetries.device_id = d.id AND
							telemetries.timestamp >= reading_start_time AND
							telemetries.timestamp <= reading_end_time AND
							telemetries.key_id = telemetry_key_id
						ORDER BY telemetries.timestamp DESC
						LIMIT 1
						) AS end_query ON TRUE
				) AS telemetry_data ON TRUE
			WHERE d.id  = _device_id;


            -- We only include service fee if the choosen range lies within ~2 days of the cycle duration 
			reading_duration := (reading_end_time - reading_start_time) * interval '1 millisecond';
			IF reading_duration BETWEEN (cycle_interval - interval '2 days')
            AND (cycle_interval + interval '2 days') 
            THEN
				service_fee := service_class_fee;
			ELSE
				service_fee := 0;
			END IF;


			FOR consumption_slab_record IN (
				SELECT DISTINCT ON (cc.id)
					COALESCE(cc_gbat.fee_per_kwh, 0) AS fee_per_kwh, 
					cc.minimum_kwh AS minimum_kwh,
					cc.maximum_kwh AS maximum_kwh
				FROM 
					consumption_categories_grid_billing_accounts_types cc_gbat 
				JOIN 
					consumption_categories cc ON cc.id = cc_gbat.consumption_category_id 
				WHERE 
					cc_gbat.grid_billing_account_type_id = grid_billing_acount_type
				AND 
					total_grid_consumption_in_cycle > cc.minimum_kwh 
			) LOOP

				-- Slab is applicable to the grid within cycle, but not provided range
				IF consumption_slab_record.minimum_kwh > consumption THEN 
					CONTINUE;
				END IF; 

				-- Consumption is in the final slab 
				IF consumption_slab_record.maximum_kwh IS NULL THEN 
					grid_consumption_in_slab := consumption - consumption_slab_record.minimum_kwh; 
				END IF; 


				-- Consumption spans the entire range 
				IF consumption > consumption_slab_record.maximum_kwh THEN
					grid_consumption_in_slab := consumption_slab_record.maximum_kwh - consumption_slab_record.minimum_kwh;
				END IF; 

				-- Consumption is not in the final slab, and does not span the entire range
				IF consumption_slab_record.maximum_kwh >= consumption THEN
					grid_consumption_in_slab := consumption - consumption_slab_record.minimum_kwh;
				END IF; 

				cost_in_sar := cost_in_sar + (grid_consumption_in_slab * consumption_slab_record.fee_per_kwh); 

			END LOOP; 

			INSERT INTO temp_table (meter_id, consumption, cost_in_sar, VAT_cost, service_class_fee, start_date, end_date)
			VALUES (
			    meter_id,
			    ROUND(consumption::NUMERIC, 2),
				ROUND(cost_in_sar::NUMERIC, 2),
				ROUND(((cost_in_sar + service_fee) * 0.15)::NUMERIC, 2),
			    service_fee,
			    reading_start_time,
			    reading_end_time
			);
			
			cost_in_sar := 0;
			consumption := 0;
			
			cycle_start_date := cycle_start_date + cycle_interval;
			cycle_end_date := cycle_end_date + cycle_interval - INTERVAL '1 second';
		END LOOP;
		
		continue_loop := true;
	END LOOP;
	
	RETURN QUERY SELECT * FROM temp_table;
	DROP TABLE temp_table;
	
END;
$function$
