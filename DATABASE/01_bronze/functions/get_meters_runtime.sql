-- bronze.get_meters_runtime(meters_list uuid[], start_timestamp bigint, end_timestamp bigint)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_meters_runtime(meters_list uuid[], start_timestamp bigint, end_timestamp bigint)
 RETURNS TABLE(meter_id uuid, device_id uuid, on_time bigint, off_time bigint, run_time bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
	_meter UUID;
	_meter_id UUID; 
	_device_id UUID; 
	_on_time BIGINT;
	_off_time BIGINT;
	_run_time BIGINT;
BEGIN
	CREATE TEMPORARY TABLE temp_table (meter_id UUID, device_id UUID, on_time BIGINT, off_time BIGINT, run_time BIGINT);

	FOREACH _meter IN ARRAY meters_list LOOP
	
		SELECT 
			em.id AS meter_id,
			em.device_id AS device_id,
			(end_query.end_on_time - start_query.start_on_time),
			(end_query.end_off_time - start_query.start_off_time),
			(end_query.end_run_time - start_query.start_run_time)
		INTO
			_meter_id, 
			_device_id,
			_on_time, 
			_off_time, 
			_run_time
		FROM 
			energy_meters em 
		JOIN LATERAL
			(
				SELECT 
					dt.on_time AS start_on_time,
					dt.off_time AS start_off_time,
					dt.run_time AS start_run_time
				FROM 
					device_time dt
				WHERE
					dt.device_id = em.device_id
				AND
					timestamp >= start_timestamp 
				AND
					timestamp <= end_timestamp
				ORDER BY
					timestamp ASC
				LIMIT 1
			) AS start_query ON TRUE
		JOIN LATERAL
			(
				SELECT 
					dt.on_time AS end_on_time,
					dt.off_time AS end_off_time,
					dt.run_time AS end_run_time
				FROM 
					device_time dt
				WHERE
					dt.device_id = em.device_id
				AND
					timestamp >= start_timestamp 
				AND
					timestamp <= end_timestamp
				ORDER BY
					timestamp DESC
				LIMIT 1
			) AS end_query ON TRUE
		WHERE 
			em.id = _meter;

		INSERT INTO temp_table (meter_id, device_id, on_time, off_time, run_time) VALUES (_meter_id, _device_id, _on_time, _off_time, _run_time);
	END LOOP;

	RETURN QUERY SELECT * FROM temp_table;
	DROP TABLE temp_table;
	
END;
$function$
