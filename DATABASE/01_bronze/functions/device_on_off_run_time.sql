-- bronze.device_on_off_run_time(new_device_online boolean, new_device_id uuid, new_timestamp bigint, new_value double precision, new_telemetry_key_name text)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.device_on_off_run_time(new_device_online boolean, new_device_id uuid, new_timestamp bigint, new_value double precision DEFAULT NULL::double precision, new_telemetry_key_name text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
	previous_timestamp BIGINT;
    previous_online BOOLEAN;
    previous_on_time REAL;
    previous_off_time REAL;
    previous_run_time REAL;
    previous_value REAL;
	new_on_time REAL;
    new_off_time REAL;
    new_run_time REAL;
	test BOOLEAN;
BEGIN
    SELECT 
        timestamp,
        online,
        value,
        on_time,
        off_time,
        run_time 
    INTO
        previous_timestamp,
        previous_online,
		previous_value,
        previous_on_time,
        previous_off_time,
        previous_run_time
    FROM
        device_time WHERE device_id = new_device_id
    ORDER BY timestamp DESC LIMIT 1;
	IF new_device_online = True THEN
        -- Online -> Online 
        IF previous_online = True THEN
            new_on_time := (new_timestamp - previous_timestamp) + previous_on_time;
            new_off_time := previous_off_time;
			IF (new_value IS NOT NULL AND new_value > 0) AND (previous_value <> 0 AND previous_value IS NOT NULL)    THEN
            	new_run_time := (new_timestamp - previous_timestamp) + previous_run_time;
    		ELSE
            	new_run_time := previous_run_time;
			END IF;		
		ELSE
            -- Offline -> Online
            -- IF previous_online == False
            new_on_time := previous_on_time;
            new_off_time := (new_timestamp - previous_timestamp) + previous_off_time;
            new_run_time := previous_run_time;
        END IF;
    ELSE
        -- IF new_device_online == False
            --  Online -> Offline
        IF previous_online = True THEN
            new_on_time := (new_timestamp - previous_timestamp) + previous_on_time;
            new_off_time := previous_off_time;
            new_run_time := previous_run_time;
        ELSE
            -- IF previous_online == False 
            --  Offline -> Offline
            new_on_time := previous_on_time;
            new_off_time := (new_timestamp - previous_timestamp) + previous_off_time;
            new_run_time := previous_run_time;
        END IF;
    END IF;

    INSERT INTO device_time (device_id,timestamp,online,value,telemetry_key_name,on_time,off_time,run_time) VALUES (
    new_device_id,
    new_timestamp,
    new_device_online,
    new_value,
    new_telemetry_key_name,
    new_on_time,
    new_off_time,
    new_run_time);
END;
$function$
