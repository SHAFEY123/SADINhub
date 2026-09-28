-- bronze.get_meters_consumption_in_different_timestamps(start_end_timestamps bigint[], devices uuid[], tele_key text)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_meters_consumption_in_different_timestamps(start_end_timestamps bigint[], devices uuid[], tele_key text)
 RETURNS TABLE(dbl double precision)
 LANGUAGE plpgsql
AS $function$
DECLARE
	start_data DECIMAL;
	end_data DECIMAL;
	consume DECIMAL;
	all_consume DECIMAL := 0;
	tele_key TEXT := tele_key;
	devices UUID[] := devices;
	_device UUID;
BEGIN
	CREATE TEMPORARY TABLE temp_table (consume double precision);
	FOR i IN 1 .. array_length(start_end_timestamps, 1) / 2
	LOOP
		FOREACH _device in ARRAY devices
		LOOP
            BEGIN
                SELECT
                    * INTO consume
                FROM
                    CALC_meter_consume(start_end_timestamps[i*2-1],start_end_timestamps[i*2],_device,tele_key);
            EXCEPTION
                WHEN SQLSTATE '02000' THEN
                    consume := 0; -- Handle "no data found" exception
            END;
			all_consume := all_consume + consume;
    	END LOOP;
		INSERT INTO temp_table (consume) VALUES (all_consume);
		all_consume := 0;
	END LOOP;
	RETURN QUERY SELECT * FROM temp_table;
	drop table temp_table;
END;
$function$
