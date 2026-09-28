-- bronze.get_uniform_dbl_data_per_device_1_timestamp(device_1 text, devices text[], tele_key integer, start_timestamp bigint, end_timestamp bigint)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_uniform_dbl_data_per_device_1_timestamp(device_1 text, devices text[], tele_key integer, start_timestamp bigint, end_timestamp bigint)
 RETURNS TABLE(stamp bigint, value_d1 numeric, value_d2 numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    timestamp1 BIGINT;
	total DECIMAL := 0;
	_device UUID;
    d1 DECIMAL;
	d2 DECIMAL;
    d1_id UUID := device_1;
	d2_id UUID[] := devices;
	tele_key INTEGER := tele_key; 
	start_timestamp BIGINT := start_timestamp;
	end_timestamp BIGINT := end_timestamp;
BEGIN
	CREATE TEMPORARY TABLE temp_table (
        stamp BIGINT , value_d1 DECIMAL , value_d2 DECIMAL
    );
    FOR timestamp1 IN 
        SELECT telemetries.timestamp as timestamp1
        FROM telemetries
        WHERE device_id = d1_id
        AND telemetries.timestamp >= start_timestamp
        AND telemetries.timestamp <= end_timestamp
        AND key_id = tele_key
    LOOP
		select dbl INTO d1
        FROM telemetries
        WHERE device_id = d1_id
        AND key_id = tele_key
        AND timestamp <= timestamp1
        ORDER BY timestamp DESC
        LIMIT 1;
		FOREACH _device in ARRAY d2_id
			LOOP
        	select dbl INTO d2 
        	FROM telemetries
        	WHERE device_id = _device
        	AND key_id = tele_key
        	AND timestamp <= timestamp1
        	ORDER BY timestamp DESC
        	LIMIT 1;
			total := total + d2;
			END LOOP;
			
			exit when total IS NULL; 
	
		INSERT INTO temp_table (stamp, value_d1, value_d2) VALUES (timestamp1,d1,total);
		total := 0;
    END LOOP;
	RETURN QUERY SELECT * FROM temp_table;
	drop table temp_table;
END $function$
