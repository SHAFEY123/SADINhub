-- bronze.get_meters_consumption_in_different_timestamps_with_sar_cost(cycle_data json[], start_end_timestamps bigint[], devices uuid[], tele_key integer)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_meters_consumption_in_different_timestamps_with_sar_cost(cycle_data json[], start_end_timestamps bigint[], devices uuid[], tele_key integer)
 RETURNS TABLE(dbl double precision, sar double precision)
 LANGUAGE plpgsql
AS $function$
DECLARE
	start_data DECIMAL;
	end_data DECIMAL;
	consume DECIMAL;
	cycle_consume DECIMAL;
	service_fee_per_day DECIMAL;
	fee_per_kwh DECIMAL;
	days_difference INTEGER;
	kwh_consumption DECIMAL := 0;
	sar_consumption DECIMAL := 0;
	tele_key INTEGER := tele_key;
	devices UUID[] := devices;
	_device UUID;
	device_index INTEGER := 1;
	timestamp_meters_cycles JSON[];
BEGIN
	CREATE TEMPORARY TABLE temp_table (kwh_consumption double precision, sar_consumption double precision);
	FOR i IN 1 .. array_length(start_end_timestamps, 1) / 2
	LOOP
		timestamp_meters_cycles := ARRAY[cycle_data[1] -> i - 1];
		FOREACH _device in ARRAY devices
		LOOP
			SELECT telemetries.dbl INTO start_data FROM telemetries WHERE "timestamp" >= (timestamp_meters_cycles[1] -> 'cycle_data' -> device_index ->> 'cycle_start')::BIGINT AND key_id = tele_key AND device_id = _device ORDER BY timestamp LIMIT 1;
			SELECT telemetries.dbl INTO end_data FROM telemetries WHERE "timestamp" <= (timestamp_meters_cycles[1] -> 'cycle_data' -> device_index ->> 'cycle_end')::BIGINT AND key_id = tele_key AND device_id = _device ORDER BY timestamp DESC LIMIT 1;
			cycle_consume := end_data - start_data;
			
			SELECT telemetries.dbl 
            INTO start_data 
            FROM telemetries 
            WHERE "timestamp" >= start_end_timestamps[i*2-1]
            AND "timestamp" <= start_end_timestamps[i*2]
            AND key_id = tele_key 
            AND device_id = _device 
            ORDER BY timestamp ASC
            LIMIT 1;

			SELECT telemetries.dbl 
            INTO end_data 
            FROM telemetries 
            WHERE "timestamp" <= start_end_timestamps[i*2] 
            AND "timestamp" >= start_end_timestamps[i*2-1] 
            AND key_id = tele_key 
            AND device_id = _device 
            ORDER BY timestamp DESC 
            LIMIT 1;

			consume := end_data - start_data;

			device_index := device_index + 1;
			
			SELECT 
				cc_gbat.fee_per_kwh,
				gba_sc.fee
			INTO
				fee_per_kwh,
				service_fee_per_day,
				days_difference
			FROM
				energy_meters em
			JOIN 
				grid_billing_accounts gba ON gba.id = em.grid_billing_account_id
			JOIN 
				grid_billing_accounts_service_classes gba_sc ON gba_sc.id = gba.service_class_id
			JOIN 
				consumption_categories cc
					ON cycle_consume > cc.minimum_kwh
					AND cycle_consume < cc.maximum_kwh
			JOIN 
				consumption_categories_grid_billing_accounts_types cc_gbat 
					ON cc_gbat.consumption_category_id = cc.id 
					AND cc_gbat.grid_billing_account_type_id = gba.type_id
			WHERE em.device_id = _device;

			kwh_consumption := kwh_consumption + COALESCE(consume, 0);
			sar_consumption := sar_consumption + COALESCE((consume * fee_per_kwh), 0);
    	END LOOP;
		INSERT INTO temp_table (kwh_consumption, sar_consumption) VALUES (kwh_consumption, sar_consumption);
		kwh_consumption := 0;
		sar_consumption := 0;
		device_index := 1;
	END LOOP;
	RETURN QUERY SELECT * FROM temp_table;
	drop table temp_table;
END;
$function$
