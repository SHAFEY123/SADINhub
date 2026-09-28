--
-- PostgreSQL database dump
--

\restrict uDVmZxGrV9TpdFinWtZIlsAjfvCq54gNFc7JuzujOksoYUVQilpMT3YdJ0ENXwd

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: bronze; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bronze;


--
-- Name: SCHEMA bronze; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA bronze IS 'standard public schema';


--
-- Name: add_alarm_to_device(); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.add_alarm_to_device() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE 
	device_alarms UUID[];
	device_alarm_levels integer[];
	category_id UUID; 
	device_parent_units UUID[];
BEGIN	
		WITH RECURSIVE ancestors AS (
			SELECT
				id,
				parent_id
			FROM units
			WHERE id = '2a6cf7cb-f6d1-4540-b5dc-7e22c1ef3a9b'
		
			UNION ALL
		
			SELECT
				u.id,
				u.parent_id
			FROM units u
			JOIN ancestors a ON u.id = a.parent_id
		)
		SELECT 
			ARRAY_AGG(id)
		INTO 
			device_parent_units
		FROM ancestors;
		
		SELECT 
			dt.category_id 
		INTO 
			category_id
		FROM
			devices_types dt
		WHERE 
			dt.id = NEW.type_id;
			
		SELECT 
			ARRAY_AGG(ac.id), 
			ARRAY_AGG(adm.alarm_level_id)
		INTO 
			device_alarms, 
			device_alarm_levels
		FROM 
			alarm_device_mapping adm 
		JOIN 
			alarm_configurations ac ON ac.id = adm.alarm_configuration_id 
		WHERE 
			(adm.device_type_id = NEW.type_id OR adm.device_category_id = category_id)
		AND 
			(adm.unit_id = ANY(device_parent_units::UUID[]) OR adm.unit_id IS NULL);
		
		IF device_alarms IS NOT NULL THEN
			FOR i IN 1 .. array_length(device_alarms, 1)
				LOOP
					INSERT INTO public.alarm_device(device_id, alarm_level_id, alarm_configuration_id, active) VALUES (NEW.id, device_alarm_levels[i], device_alarms[i], TRUE);
				END LOOP;
			END IF;
	RETURN NEW;
END;
$$;


--
-- Name: archive_deleted_schedule(); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.archive_deleted_schedule() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
        DECLARE
            current_user_id UUID;
        BEGIN
            -- Retrieve the current user's UUID from the session; returns NULL if not set.
            current_user_id := current_setting('myapp.current_user_id', true)::UUID;

            -- Insert the row into the archive table with the deleted_by information and archive timestamp.
            INSERT INTO DELETED_schedules (id,name,description,start_datetime,end_datetime,schedule_duration,triggers,active,created_on,created_by,deleted_at,deleted_by,deleted_schedule_units,deleted_schedule_controllers)
            SELECT
                schedules.id,schedules.name,schedules.description,schedules.start_datetime,schedules.end_datetime,schedules.schedule_duration,schedules.triggers,schedules.active,schedules.created_on,schedules.created_by,CURRENT_TIMESTAMP,current_user_id,
                ARRAY_AGG(schedule_units.unit_id),
                JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                        'controller_id', schedule_controllers.controller_id,
                        'execution_sequence', schedule_controllers.execution_sequence,
                        'controller_action', schedule_controllers.controller_action
                    ))
            FROM 
                schedules
            JOIN
                schedule_units ON schedule_units.schedule_id = schedules.id
            JOIN
                schedule_controllers ON schedule_controllers.schedule_id = schedules.id
            WHERE 
                schedules.id = OLD.id
            GROUP BY schedules.id;
                
            RETURN OLD;  -- Allow the delete to proceed.
        END;
        $$;


--
-- Name: assign_role_to_all_units(); Type: PROCEDURE; Schema: bronze; Owner: -
--

CREATE PROCEDURE bronze.assign_role_to_all_units()
    LANGUAGE plpgsql
    AS $$
DECLARE owner_role_user_id JSONB[];
DECLARE sadin_admin_user_id UUID;
DECLARE user_info JSONB;
DECLARE row units%rowtype;
BEGIN 
    SELECT ARRAY(
        SELECT
            jsonb_array_elements(
                JSON_ARRAYAGG(
                    JSONB_BUILD_OBJECT('role_id',roles.id,'user_id',users.id)))) INTO owner_role_user_id
        FROM
            roles
        JOIN
            users ON users.role_id = roles.id
        WHERE
            roles.global_role = True
        GROUP BY
            roles.created_on
        ORDER BY
            roles.created_on;
    sadin_admin_user_id := owner_role_user_id[1]->>'user_id';
    FOREACH user_info IN ARRAY owner_role_user_id LOOP
        FOR row in SELECT * FROM units LOOP
            INSERT INTO public.role_units(role_id, unit_id, unit_level, created_on, created_by)
            VALUES ((user_info->>'role_id')::UUID, row.id, row.level, NOW(), sadin_admin_user_id) ON CONFLICT (role_id, unit_id) DO NOTHING;
            END LOOP;
    END LOOP;
END; $$;


--
-- Name: authorize_role_units(uuid, uuid); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.authorize_role_units(user_role_id uuid, wanted_unit_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
	role_units UUID[];
	tmp_role_units UUID[];
	role_unit UUID;
BEGIN
	SELECT ARRAY_AGG(role_units.unit_id) INTO role_units FROM role_units WHERE role_units.role_id = user_role_id;
	IF wanted_unit_id = ANY(role_units) THEN
		RETURN TRUE;
	ELSE
		FOREACH role_unit IN ARRAY role_units
		LOOP 
		 	WITH RECURSIVE generation AS (SELECT id FROM units WHERE parent_id =role_unit
			UNION ALL SELECT child.id FROM units child 
 			JOIN generation  ON generation.id = child.parent_id ) 
 			SELECT ARRAY_AGG(DISTINCT generation.id) INTO tmp_role_units FROM generation;
			role_units := ARRAY_CAT(role_units,tmp_role_units);
		END LOOP;
		IF wanted_unit_id = ANY(role_units) THEN
			RETURN TRUE;
		ELSE
			RETURN FALSE;
		END IF;
	
		RETURN FALSE;
	END IF;
END;
$$;


--
-- Name: calc_meter_consume(bigint, bigint, uuid, text); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.calc_meter_consume(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    telemetry_key_id INTEGER;
    start_data DECIMAL;
    end_data DECIMAL;
    consume DECIMAL;
BEGIN
    -- Get telemetry key ID
    SELECT * INTO telemetry_key_id
    FROM get_telemetries_key_id_by_key_name(telemetry_key);
    
    -- Get start data
    SELECT 
        telemetries.dbl INTO start_data
    FROM 
        telemetries
    WHERE 
        "timestamp" >= start_timestamp
        AND key_id = telemetry_key_id
        AND device_id = meter_id
        AND "timestamp" <= end_timestamp
    ORDER BY "timestamp"
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'There is no data >= % for device % and key % in telemetries',
            start_timestamp, meter_id, telemetry_key
            USING ERRCODE = '02000';
            
    END IF;

    -- Get end data
    SELECT
        telemetries.dbl INTO end_data
    FROM
        telemetries
    WHERE
        "timestamp" <= end_timestamp
        AND key_id = telemetry_key_id
        AND device_id = meter_id
        AND "timestamp" >= start_timestamp
    ORDER BY "timestamp" DESC
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'There is no data <= % for device % and key % in telemetries',
            end_timestamp, meter_id, telemetry_key
            USING ERRCODE = '02000';
    END IF;

    -- Calculate consumption
    consume := end_data - start_data;

    RETURN consume;
END;
$$;


--
-- Name: calc_meter_consume_with_start_end_consume_info(bigint, bigint, uuid, text); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.calc_meter_consume_with_start_end_consume_info(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: check_facility_budget_duplication(); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.check_facility_budget_duplication() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM budgets
        WHERE budgets.type_id = NEW.type_id
    ) THEN
        RAISE EXCEPTION 'Budget of the same type already exist';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: check_facility_id_not_null(); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.check_facility_id_not_null() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.facility_id IS NULL THEN
        RAISE EXCEPTION 'facility_id cannot be null';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: check_sensor_in_device_sensors(); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.check_sensor_in_device_sensors() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM device_sensors
        WHERE device_sensors.sensor_id = NEW.water_sensor_id
    ) THEN
        RAISE EXCEPTION 'Sensor % already has a relation in DeviceSenor',NEW.water_sensor_id;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: check_sensor_in_tank_sensors(); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.check_sensor_in_tank_sensors() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM water_tank_water_sensors
        WHERE water_tank_water_sensors.water_sensor_id = NEW.sensor_id
    ) THEN
        RAISE EXCEPTION 'Sensor % already has a relation in TankSensor',NEW.sensor_id;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: device_on_off_run_time(boolean, uuid, bigint, double precision, text); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.device_on_off_run_time(new_device_online boolean, new_device_id uuid, new_timestamp bigint, new_value double precision DEFAULT NULL::double precision, new_telemetry_key_name text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: fetch_user_permissions(uuid); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.fetch_user_permissions(user_role_id uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
	role_unit UUID;
	role_units UUID[];  -- role_units to be return
	temp_role_units UUID[];
	temp_module_permissions JSONB; -- module_permissions to be return
BEGIN	
	SELECT ARRAY_AGG(DISTINCT role_units.unit_id) INTO role_units FROM role_units WHERE role_units.role_id = user_role_id;

    IF role_units IS NULL THEN
        RAISE EXCEPTION 'role_units is NULL please fix seeder';
    END IF;

	-- NOTE the block below is commented because it will help a lot to make front-end dev easier 
    -- if there is performance issue in feature this block can be removed
    -- and add all allow units to role_units instead of parent_unit
    -- to make sure that user also have access to new added units create Trigger on units table which
    -- will be trigger when new unit is add as following
    -- check if new.unit.parent_id exist in role_units table if true then add new.units to each role connect to the new.unit.parent_id
    -- function link_unit_with_parent_roles() will do this logic  
	-- therefore RECURSIVE will not be required in login process and new added units will not be abandoned. 

	-- FOREACH role_unit IN ARRAY role_units
	-- 	LOOP 
	-- 	 	WITH RECURSIVE generation AS (SELECT id FROM units WHERE parent_id =role_unit
	-- 		UNION ALL SELECT child.id FROM units child 
 	-- 		JOIN generation  ON generation.id = child.parent_id ) 
 	-- 		SELECT ARRAY_AGG(DISTINCT generation.id) INTO temp_role_units FROM generation;
	-- 		role_units := ARRAY_CAT(role_units,temp_role_units);
	-- 	END LOOP;
	
	SELECT JSONB_OBJECT_AGG(modules.title,
        JSONB_BUILD_OBJECT('read',permissions.read,'create',permissions.create,'update',permissions.update,
	    'delete',permissions.delete,'control',permissions.control)) into temp_module_permissions
	
	FROM role_module_permission 
	    JOIN modules 
	ON modules.id = role_module_permission.module_id
	    JOIN permissions 
	ON permissions.id = role_module_permission.permission_id
	    JOIN role_units 
	ON role_units.role_id = user_role_id
	    WHERE role_module_permission.role_id = user_role_id;

    IF temp_module_permissions IS NULL THEN
        RAISE EXCEPTION 'temp_module_permissions is NULL please fix seeder';
    END IF;

	RETURN JSONB_BUILD_OBJECT('module', temp_module_permissions, 'units', role_units);
END;
$$;


--
-- Name: get_all_child_units_by_parent_id(uuid); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_all_child_units_by_parent_id(src_unit_id uuid) RETURNS TABLE(id uuid, name character varying, is_building boolean, level integer, parent_id uuid, type_id uuid, unit_type_name character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE generation AS (
        SELECT u.id, u.name, u.is_building, u.level, u.parent_id, u.type_id
        FROM units u
        WHERE u.parent_id = src_unit_id

        UNION ALL

        SELECT c.id, c.name, c.is_building, c.level, c.parent_id, c.type_id
        FROM units c
        INNER JOIN generation g ON g.id = c.parent_id
    )
    SELECT g.id, g.name, g.is_building, g.level, g.parent_id, g.type_id, ut.name AS unit_type_name
    FROM generation g
    JOIN units_types ut ON g.type_id = ut.id;
END;
$$;


--
-- Name: get_each_day_consume_per_units(jsonb); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_each_day_consume_per_units(days_timestamps jsonb) RETURNS TABLE(unit_name text, day_date text, day_consume numeric, day_start_consume numeric, day_start_consume_timestamp text, day_end_consume numeric, day_end_consume_timestamp text, meter_serial_number text, meter_label text, grid_account_number text, multiplication_factor integer)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: get_latest_telemetry(uuid, text); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_latest_telemetry(in_device_id uuid, telemetrie_key_name text) RETURNS TABLE(result text)
    LANGUAGE plpgsql
    AS $$
DECLARE
telemetrie_key_name_id INTEGER;
telemetrie_key_type TEXT;
latest_telemetrie_row telemetries_latest%rowtype;
BEGIN
    SELECT id INTO telemetrie_key_name_id FROM telemetries_dictionaries WHERE key = telemetrie_key_name;

    -- using json instead jsonb is very bad for reading performance
    SELECT value ->> 'type' INTO telemetrie_key_type
		FROM device, json_array_elements(user_conf->'keys') AS keys_config
    WHERE keys_config->>'name' = telemetrie_key_name AND device.id = in_device_id;

    RETURN QUERY EXECUTE format('
        SELECT
            %s::TEXT 
        FROM 
            telemetries_latest 
        WHERE
            telemetries_latest.key_id = %s
        AND
            telemetries_latest.device_id = %L'
        ,telemetrie_key_type, telemetrie_key_name_id,in_device_id);

END $$;


--
-- Name: get_meters_consumption_in_different_timestamps(bigint[], uuid[], text); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_meters_consumption_in_different_timestamps(start_end_timestamps bigint[], devices uuid[], tele_key text) RETURNS TABLE(dbl double precision)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: get_meters_consumption_in_different_timestamps_with_sar_cost(json[], bigint[], uuid[], integer); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_meters_consumption_in_different_timestamps_with_sar_cost(cycle_data json[], start_end_timestamps bigint[], devices uuid[], tele_key integer) RETURNS TABLE(dbl double precision, sar double precision)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: get_meters_consumption_in_range(uuid[], bigint, bigint); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_meters_consumption_in_range(meter_ids uuid[], input_start_timestamp bigint, input_end_timestamp bigint) RETURNS TABLE(meter_id uuid, consumption double precision, cost_in_sar double precision, vat_cost double precision, service_class_fee double precision, start_date bigint, end_date bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: get_meters_runtime(uuid[], bigint, bigint); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_meters_runtime(meters_list uuid[], start_timestamp bigint, end_timestamp bigint) RETURNS TABLE(meter_id uuid, device_id uuid, on_time bigint, off_time bigint, run_time bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: get_meters_under_unit(uuid); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_meters_under_unit(unit_id uuid) RETURNS TABLE(id uuid)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE unit_descendants AS (
      SELECT u.id
      FROM units u
      WHERE u.id = unit_id

      UNION ALL

      SELECT un.id
      FROM units un
      INNER JOIN unit_descendants ud ON un.parent_id = ud.id
  )
  SELECT em.id
  FROM unit_descendants ud 
  JOIN energy_meters em ON em.unit_id = ud.id;

END;
$$;


--
-- Name: get_telemetries_key_id_by_key_name(text); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_telemetries_key_id_by_key_name(key_name text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	key_id INTEGER;
BEGIN
	select id into key_id from telemetries_dictionaries where key = key_name;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'key % doesnt exist in telemetries_dictionaries', key_name;
    END IF;

    RETURN key_id;
END;
$$;


--
-- Name: get_uniform_dbl_data_per_device_1_timestamp(text, text[], integer, bigint, bigint); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_uniform_dbl_data_per_device_1_timestamp(device_1 text, devices text[], tele_key integer, start_timestamp bigint, end_timestamp bigint) RETURNS TABLE(stamp bigint, value_d1 numeric, value_d2 numeric)
    LANGUAGE plpgsql
    AS $$
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
END $$;


--
-- Name: get_working_custom_groups_consume_per_units(jsonb); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_working_custom_groups_consume_per_units(custom_groups_timestamps jsonb) RETURNS json
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: get_working_non_working_days_consume_per_units(jsonb); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.get_working_non_working_days_consume_per_units(working_non_working_hours_timestamps jsonb) RETURNS TABLE(unit_name text, day_date text, working_hours_consume numeric, non_working_hours_consume numeric, meter_serial_number text, meter_label text, grid_account_number text, multiplication_factor integer)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: initialize_init_on_off_run_time_for_all_devices(); Type: PROCEDURE; Schema: bronze; Owner: -
--

CREATE PROCEDURE bronze.initialize_init_on_off_run_time_for_all_devices()
    LANGUAGE plpgsql
    AS $$
DECLARE row device%rowtype;
BEGIN 
    FOR row in SELECT * FROM device
    LOOP
        INSERT INTO public.device_time(device_id, timestamp, online, telemetry_key_name, value,on_time,off_time,run_time) 
        SELECT row.id, extract(epoch from now()) * 1000 ,False,NULL,NULL,0,0,0
        WHERE
            NOT EXISTS (
        SELECT 1 FROM public.device_time WHERE public.device_time.device_id = row.id
        );

    END LOOP;
END; $$;


--
-- Name: link_unit_with_parent_roles(); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.link_unit_with_parent_roles() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE 
	temp_role_ids UUID[];
	temp_role_id UUID;
BEGIN	
	SELECT ARRAY_AGG(DISTINCT role_units.role_id) INTO temp_role_ids FROM role_units WHERE role_units.unit_id = NEW.parent_id;
	IF temp_role_ids IS NOT NULL THEN
	FOREACH temp_role_id IN ARRAY temp_role_ids
		LOOP
		INSERT INTO public.role_units(role_id, unit_id, unit_level, created_on, created_by) VALUES (temp_role_id, NEW.id, NEW.level, NEW.created_on, NEW.created_by);
		END LOOP;
	END IF;
	RETURN NEW;
END;
$$;


--
-- Name: query_calc_meter_consume(bigint, bigint, uuid, text); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.query_calc_meter_consume(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text) RETURNS double precision
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN CALC_meter_consume(start_timestamp ,end_timestamp ,meter_id ,telemetry_key)::float;
EXCEPTION
    WHEN SQLSTATE '02000' THEN
        RETURN NULL; -- Or 0 if you prefer a default numerical value
END;
$$;


--
-- Name: query_calc_meter_consume_with_start_end_consume_info(bigint, bigint, uuid, text); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.query_calc_meter_consume_with_start_end_consume_info(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN CALC_meter_consume_with_start_end_consume_info(start_timestamp ,end_timestamp ,meter_id ,telemetry_key);
EXCEPTION
    WHEN SQLSTATE '02000' THEN
        RETURN NULL; 
END;
$$;


--
-- Name: unit_recursion_info(uuid); Type: FUNCTION; Schema: bronze; Owner: -
--

CREATE FUNCTION bronze.unit_recursion_info(_unit_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
SELECT jsonb_agg(
    CASE WHEN children IS NULL
    	THEN to_jsonb(sub) - 'children'
        ELSE to_jsonb(sub) END
	)
FROM  (
   SELECT units.name as label ,units.id , units.level ,units.html_hex_color , icons.css_class , unit_recursion_info(units.id) AS children
   FROM units
   LEFT JOIN icons ON icons.id = units.icon_id
   WHERE units.parent_id = _unit_id
   ORDER  BY units.id
   ) sub
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: addresses; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.addresses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    short_address character varying(8),
    building_number integer NOT NULL,
    street_name character varying(255) NOT NULL,
    district_name character varying(255) NOT NULL,
    city_name character varying(255) NOT NULL,
    zip_code integer NOT NULL,
    additional_number integer NOT NULL,
    unit_number integer NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    title character varying(255) NOT NULL,
    CONSTRAINT addresses_additional_number_check CHECK ((additional_number > 0)),
    CONSTRAINT addresses_building_number_check CHECK ((building_number > 0)),
    CONSTRAINT addresses_unit_number_check CHECK ((unit_number > 0)),
    CONSTRAINT addresses_zip_code_check CHECK ((zip_code > 0))
);


--
-- Name: alarm_acknowledgement_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_acknowledgement_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL
);


--
-- Name: alarm_acknowledgements; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_acknowledgements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    alarm_configuration_id uuid NOT NULL,
    device_id uuid NOT NULL,
    acknowledged_until bigint NOT NULL,
    "timestamp" bigint NOT NULL,
    acknowledged_by uuid NOT NULL
);


--
-- Name: alarm_configurations; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_configurations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    description character varying(255),
    details json NOT NULL,
    severity_id uuid NOT NULL,
    alarm_type_id uuid NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    active boolean NOT NULL
);


--
-- Name: alarm_configurations_history; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_configurations_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payload json NOT NULL,
    alarm_configuration_id uuid NOT NULL,
    created_by uuid NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: alarm_contact_groups; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_contact_groups (
    alarm_configuration_id uuid NOT NULL,
    contact_label_id uuid NOT NULL,
    contact_after integer NOT NULL,
    level integer NOT NULL,
    CONSTRAINT alarm_contact_groups_contact_after_check CHECK ((contact_after >= 0)),
    CONSTRAINT alarm_contact_groups_level_check CHECK ((level >= 0))
);


--
-- Name: alarm_contact_methods; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_contact_methods (
    contact_after integer NOT NULL,
    notification_interval integer NOT NULL,
    contact_method_id uuid NOT NULL,
    alarm_configuration_id uuid NOT NULL,
    CONSTRAINT alarm_contact_methods_contact_after_check CHECK ((contact_after >= 0)),
    CONSTRAINT alarm_contact_methods_notification_interval_check CHECK ((notification_interval >= 0))
);


--
-- Name: alarm_contacts; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_contacts (
    alarm_configuration_id uuid NOT NULL,
    level integer NOT NULL,
    contact_after integer NOT NULL,
    contact_id uuid NOT NULL,
    CONSTRAINT alarm_contacts_contact_after_check CHECK ((contact_after >= 0)),
    CONSTRAINT alarm_contacts_level_check CHECK ((level >= 0))
);


--
-- Name: alarm_device; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_device (
    device_id uuid NOT NULL,
    alarm_level_id integer NOT NULL,
    alarm_configuration_id uuid NOT NULL,
    active boolean NOT NULL
);


--
-- Name: alarm_device_mapping; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_device_mapping (
    alarm_configuration_id uuid NOT NULL,
    device_type_id uuid,
    device_category_id uuid,
    alarm_level_id integer NOT NULL,
    unit_id uuid NOT NULL
);


--
-- Name: alarm_levels; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_levels (
    id integer NOT NULL,
    title character varying(255) NOT NULL,
    description character varying(255) NOT NULL
);


--
-- Name: alarm_log_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_log_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL
);


--
-- Name: alarm_logs; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_logs (
    details json NOT NULL,
    alarm_configuration_id uuid NOT NULL,
    log_type_id uuid NOT NULL,
    device_id uuid NOT NULL,
    "timestamp" bigint NOT NULL
);


--
-- Name: alarm_notifications; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_notifications (
    alarm_configuration_id uuid NOT NULL,
    device_id uuid NOT NULL,
    notification_id uuid NOT NULL
);


--
-- Name: alarm_telemetry_keys; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_telemetry_keys (
    alarm_configuration_id uuid NOT NULL,
    telemetry_key_id bigint NOT NULL,
    details json NOT NULL
);


--
-- Name: alarm_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarm_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    description character varying(255),
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    active boolean NOT NULL
);


--
-- Name: alarms_severities; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarms_severities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    icon character varying(255) NOT NULL,
    hex_color character varying(7) NOT NULL,
    default_configs json,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: alarms_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.alarms_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: appliance_category; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.appliance_category (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    icon character varying(255),
    created_on timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: appliances; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.appliances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    category_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    meter_id uuid NOT NULL,
    facility_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: attempted_logins; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.attempted_logins (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    ip_address character varying(255) NOT NULL,
    is_successful boolean NOT NULL,
    details character varying(255),
    created_on timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: banned_jtis; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.banned_jtis (
    id uuid NOT NULL,
    refresh_token_jti uuid NOT NULL,
    user_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: budget_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.budget_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: budgets; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.budgets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    value integer NOT NULL,
    type_id uuid NOT NULL,
    facility_id uuid NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT budgets_value_check CHECK ((value > 0))
);


--
-- Name: clients; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.clients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    code character varying(255) NOT NULL,
    facility_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT clients_code_check CHECK ((length((code)::text) = 4))
);


--
-- Name: consumption_categories; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.consumption_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    facility_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    maximum_kwh integer NOT NULL,
    minimum_kwh integer NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT consumption_categories_maximum_kwh_check CHECK ((maximum_kwh > 0)),
    CONSTRAINT consumption_categories_minimum_kwh_check CHECK ((minimum_kwh > 0))
);


--
-- Name: consumption_categories_grid_billing_accounts_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.consumption_categories_grid_billing_accounts_types (
    consumption_category_id uuid CONSTRAINT consumption_categories_grid_bi_consumption_category_id_not_null NOT NULL,
    grid_billing_account_type_id uuid CONSTRAINT consumption_categories_grid_grid_billing_account_type__not_null NOT NULL,
    fee_per_kwh numeric(16,8) CONSTRAINT consumption_categories_grid_billing_accoun_fee_per_kwh_not_null NOT NULL,
    created_by uuid CONSTRAINT consumption_categories_grid_billing_account_created_by_not_null NOT NULL,
    created_on timestamp with time zone DEFAULT now() CONSTRAINT consumption_categories_grid_billing_account_created_on_not_null NOT NULL
);


--
-- Name: contact_labels; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.contact_labels (
    contact_id uuid NOT NULL,
    label_id uuid NOT NULL
);


--
-- Name: contact_method_mapping; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.contact_method_mapping (
    contact_id uuid NOT NULL,
    contact_method_id uuid NOT NULL
);


--
-- Name: contact_methods; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.contact_methods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    description character varying(255),
    created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: contacts; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    full_name character varying(255) NOT NULL,
    description character varying(255),
    preferences json,
    user_id uuid,
    email character varying(255) NOT NULL,
    phone_number character varying(13) NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: deleted_schedules; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.deleted_schedules (
    id uuid,
    name character varying(255),
    description text,
    start_datetime timestamp without time zone,
    end_datetime timestamp without time zone,
    schedule_duration integer,
    triggers jsonb,
    active boolean,
    created_on timestamp without time zone,
    created_by uuid,
    deleted_by uuid,
    deleted_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    deleted_schedule_units uuid[],
    deleted_schedule_controllers jsonb
);


--
-- Name: serial_number_seq; Type: SEQUENCE; Schema: bronze; Owner: -
--

CREATE SEQUENCE bronze.serial_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: device; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.device (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    active boolean DEFAULT true,
    gateway_id uuid,
    label character varying(255),
    user_conf json,
    description character varying(255),
    type_id uuid NOT NULL,
    unit_id uuid,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    facility_id uuid,
    online boolean,
    client_id uuid,
    assembly_date timestamp without time zone DEFAULT now() NOT NULL,
    serial_number bigint DEFAULT nextval('bronze.serial_number_seq'::regclass) NOT NULL,
    label_id uuid,
    properties jsonb NOT NULL
);


--
-- Name: device_control_labels; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.device_control_labels (
    device_control_id uuid NOT NULL,
    label_id uuid NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: device_control_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.device_control_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: device_controls; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.device_controls (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    device_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    icon character varying(255) NOT NULL,
    icon_color character varying(255),
    config jsonb NOT NULL,
    created_by uuid NOT NULL,
    telemetry_key character varying(400),
    description text
);


--
-- Name: device_controls_unit_pinned; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.device_controls_unit_pinned (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    unit_id uuid NOT NULL,
    pinned boolean NOT NULL,
    visible boolean NOT NULL
);


--
-- Name: device_credentials; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.device_credentials (
    cred_id character varying(255) NOT NULL,
    device_id uuid,
    cred_val character varying(400) NOT NULL,
    cred_type character varying(255) DEFAULT 'mqtt_basic'::character varying NOT NULL,
    extra_credentials character varying(255),
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    username character varying(64) NOT NULL,
    uudid character varying(64) NOT NULL
);


--
-- Name: device_sensors; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.device_sensors (
    device_id uuid NOT NULL,
    sensor_id uuid NOT NULL,
    telemetry_key character varying(400) NOT NULL,
    telemetry_key_id bigint NOT NULL,
    control_id uuid,
    category_name character varying(255) NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: device_time; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.device_time (
    device_id uuid NOT NULL,
    "timestamp" bigint NOT NULL,
    online boolean NOT NULL,
    value double precision,
    telemetry_key_name character varying(400),
    on_time bigint NOT NULL,
    off_time bigint NOT NULL,
    run_time bigint NOT NULL
);


--
-- Name: devices_categories; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.devices_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    code character varying(4) NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT devices_categories_code_check CHECK ((length((code)::text) = 4))
);


--
-- Name: devices_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.devices_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    config_preset json,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    code integer NOT NULL,
    description text NOT NULL,
    icon character varying(255),
    properties jsonb NOT NULL,
    CONSTRAINT devices_types_code_check CHECK ((code < 999)),
    CONSTRAINT devices_types_code_check1 CHECK ((code > 0))
);


--
-- Name: energy_bills_tracking; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.energy_bills_tracking (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    facility_id uuid NOT NULL,
    grid_billing_account_id uuid NOT NULL,
    start_period timestamp with time zone NOT NULL,
    end_period timestamp with time zone NOT NULL,
    beginning_reading numeric(16,2) NOT NULL,
    ending_reading numeric(16,2) NOT NULL,
    consumption_reading numeric(16,2) NOT NULL,
    cost numeric(16,2) NOT NULL,
    comparing_with_last_bill character varying(255) NOT NULL,
    system_beginning_reading numeric(16,2) NOT NULL,
    system_endng_reading numeric(16,2) NOT NULL,
    system_consumption_reading numeric(16,2) NOT NULL,
    system_estimated_cost numeric(16,2) NOT NULL,
    system_reading_time bigint,
    comparing_with_grid_bill character varying(255) NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    invoice_number bigint NOT NULL
);


--
-- Name: energy_meter_phase_map; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.energy_meter_phase_map (
    parent_device uuid NOT NULL,
    phase_parent integer NOT NULL,
    child_device uuid NOT NULL,
    phase_child integer NOT NULL
);


--
-- Name: energy_meters; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.energy_meters (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    facility_id uuid NOT NULL,
    grid_billing_account_id uuid NOT NULL,
    device_id uuid NOT NULL,
    phase integer NOT NULL,
    parent_id uuid,
    maximum_kwh integer NOT NULL,
    type_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    meter_sn character varying(255),
    meter_label character varying(255),
    CONSTRAINT energy_meters_maximum_kwh_check CHECK ((maximum_kwh > 0)),
    CONSTRAINT energy_meters_phase_check CHECK ((phase > 0))
);


--
-- Name: energy_meters_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.energy_meters_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: energy_saving_recommendations; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.energy_saving_recommendations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    facility_id uuid NOT NULL,
    title character varying(1000) NOT NULL,
    top_right_text character varying(1000) NOT NULL,
    body_text text NOT NULL,
    bottom_right_text character varying(1000) NOT NULL,
    color character varying(7) NOT NULL,
    icon_class character varying(50) NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: facilities; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.facilities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255),
    unit_id uuid,
    facility_type_id uuid NOT NULL,
    latitude numeric(10,8),
    longitude numeric(11,8),
    x_coordinate numeric(16,8),
    y_coordinate numeric(16,8),
    address_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: facilities_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.facilities_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: firmwares; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.firmwares (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    filename character varying(255) NOT NULL,
    client_id character varying(255) NOT NULL,
    version character varying(255) NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: floor_plan; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.floor_plan (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    unit_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    image_proprties jsonb NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: forget_password; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.forget_password (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    active boolean NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    expires_on timestamp without time zone NOT NULL,
    token character varying(255) NOT NULL
);


--
-- Name: grid_billing_accounts; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.grid_billing_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    label character varying(255) NOT NULL,
    number bigint NOT NULL,
    meter_serial_number character varying(255) NOT NULL,
    type_id uuid NOT NULL,
    service_class_id uuid NOT NULL,
    breaker_capacity integer NOT NULL,
    start_period timestamp with time zone NOT NULL,
    end_period timestamp with time zone NOT NULL,
    days integer NOT NULL,
    facility_id uuid,
    unit_id uuid,
    created_by uuid NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    multiplication_factor integer NOT NULL,
    CONSTRAINT grid_billing_accounts_breaker_capacity_check CHECK ((breaker_capacity > 0)),
    CONSTRAINT grid_billing_accounts_days_check CHECK ((days > 0)),
    CONSTRAINT grid_billing_accounts_multiplication_factor_check CHECK ((multiplication_factor > 0))
);


--
-- Name: grid_billing_accounts_service_classes; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.grid_billing_accounts_service_classes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    minimal_breaker_capacity integer CONSTRAINT grid_billing_accounts_service_minimal_breaker_capacity_not_null NOT NULL,
    maximum_breaker_capacity integer,
    fee integer NOT NULL,
    facility_id uuid NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT grid_billing_accounts_service_cl_maximum_breaker_capacity_check CHECK ((maximum_breaker_capacity > 0)),
    CONSTRAINT grid_billing_accounts_service_cl_minimal_breaker_capacity_check CHECK ((minimal_breaker_capacity > 0)),
    CONSTRAINT grid_billing_accounts_service_classes_fee_check CHECK ((fee > 0))
);


--
-- Name: grid_billing_accounts_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.grid_billing_accounts_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: icons; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.icons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    css_class character varying(255) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: id_seq; Type: SEQUENCE; Schema: bronze; Owner: -
--

CREATE SEQUENCE bronze.id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: key_id_seq; Type: SEQUENCE; Schema: bronze; Owner: -
--

CREATE SEQUENCE bronze.key_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: label_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.label_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: labels; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.labels (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    icon character varying(255),
    description text,
    hex_color character varying(7) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    label_type_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: migratehistory; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.migratehistory (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    migrated_at timestamp without time zone NOT NULL
);


--
-- Name: migratehistory_id_seq; Type: SEQUENCE; Schema: bronze; Owner: -
--

CREATE SEQUENCE bronze.migratehistory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: migratehistory_id_seq; Type: SEQUENCE OWNED BY; Schema: bronze; Owner: -
--

ALTER SEQUENCE bronze.migratehistory_id_seq OWNED BY bronze.migratehistory.id;


--
-- Name: modules; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.modules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    html_class character varying(255),
    color character varying(255),
    has_children boolean,
    level integer,
    parent_id uuid,
    priority integer,
    route_to character varying(255),
    created_on timestamp without time zone DEFAULT now(),
    CONSTRAINT modules_level_check CHECK ((level >= 0)),
    CONSTRAINT modules_priority_check CHECK ((priority >= 0))
);


--
-- Name: mqtt_service_accounts; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.mqtt_service_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    username character varying(255) NOT NULL,
    password character varying(255) NOT NULL,
    description text,
    active boolean NOT NULL,
    facility_id uuid NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: mqtt_service_accounts_allowed_topics; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.mqtt_service_accounts_allowed_topics (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    mqtt_topic_id uuid NOT NULL,
    access integer NOT NULL,
    active boolean NOT NULL,
    mqtt_service_account_id uuid CONSTRAINT mqtt_service_accounts_allowed__mqtt_service_account_id_not_null NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    CONSTRAINT mqtt_service_accounts_allowed_topics_access_check CHECK ((access > 0))
);


--
-- Name: mqtt_topics; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.mqtt_topics (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    topic character varying(255) NOT NULL,
    regex character varying(255) NOT NULL,
    active boolean NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    facility_id uuid NOT NULL
);


--
-- Name: multi_factor_authentication_factors; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.multi_factor_authentication_factors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    token character varying(255) NOT NULL,
    additional_config json,
    type_id uuid NOT NULL,
    active boolean DEFAULT false NOT NULL
);


--
-- Name: multi_factor_authentication_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.multi_factor_authentication_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    active boolean,
    created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: notification_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.notification_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL
);


--
-- Name: notifications; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    notification_group_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    contact_method_id uuid NOT NULL,
    notification_type_id uuid NOT NULL,
    successfully_sent boolean NOT NULL,
    read boolean NOT NULL,
    read_ts bigint,
    "timestamp" bigint NOT NULL,
    details json NOT NULL
);


--
-- Name: overlay_controllers; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.overlay_controllers (
    overlay_id uuid NOT NULL,
    controller_id uuid NOT NULL
);


--
-- Name: overlays; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.overlays (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    unit_id uuid NOT NULL,
    floor_plan_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    shape_config jsonb NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: permissions; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.permissions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    read boolean NOT NULL,
    "create" boolean NOT NULL,
    update boolean NOT NULL,
    delete boolean NOT NULL,
    control boolean NOT NULL,
    billing boolean NOT NULL,
    is_core boolean DEFAULT false NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now()
);


--
-- Name: role_module_permission; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.role_module_permission (
    role_id uuid NOT NULL,
    module_id uuid NOT NULL,
    permission_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: role_units; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.role_units (
    role_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    unit_level integer NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    description text NOT NULL,
    global_role boolean DEFAULT false NOT NULL,
    icon character varying(255) NOT NULL,
    icon_color character varying(255) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_on timestamp without time zone DEFAULT now(),
    created_by uuid,
    facility_id uuid
);


--
-- Name: schedule_controllers; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.schedule_controllers (
    id integer NOT NULL,
    schedule_id uuid NOT NULL,
    controller_id uuid NOT NULL,
    execution_sequence integer NOT NULL,
    controller_action character varying(255) NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: schedule_controllers_id_seq; Type: SEQUENCE; Schema: bronze; Owner: -
--

CREATE SEQUENCE bronze.schedule_controllers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schedule_controllers_id_seq; Type: SEQUENCE OWNED BY; Schema: bronze; Owner: -
--

ALTER SEQUENCE bronze.schedule_controllers_id_seq OWNED BY bronze.schedule_controllers.id;


--
-- Name: schedule_jobs; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.schedule_jobs (
    job_id character varying(255) NOT NULL,
    schedule_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: schedule_labels; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.schedule_labels (
    id integer NOT NULL,
    schedule_id uuid NOT NULL,
    label_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: schedule_labels_id_seq; Type: SEQUENCE; Schema: bronze; Owner: -
--

CREATE SEQUENCE bronze.schedule_labels_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schedule_labels_id_seq; Type: SEQUENCE OWNED BY; Schema: bronze; Owner: -
--

ALTER SEQUENCE bronze.schedule_labels_id_seq OWNED BY bronze.schedule_labels.id;


--
-- Name: schedule_units; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.schedule_units (
    id integer NOT NULL,
    schedule_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: schedule_units_id_seq; Type: SEQUENCE; Schema: bronze; Owner: -
--

CREATE SEQUENCE bronze.schedule_units_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schedule_units_id_seq; Type: SEQUENCE OWNED BY; Schema: bronze; Owner: -
--

ALTER SEQUENCE bronze.schedule_units_id_seq OWNED BY bronze.schedule_units.id;


--
-- Name: schedules; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    description text NOT NULL,
    start_datetime timestamp without time zone NOT NULL,
    end_datetime timestamp without time zone,
    schedule_duration integer,
    triggers jsonb NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    schedule_type character varying(255)
);


--
-- Name: tariff_categories; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.tariff_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    maximum_amp integer NOT NULL,
    minimum_amp integer NOT NULL,
    fee numeric(10,2),
    active boolean DEFAULT true NOT NULL,
    facility_id uuid,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    CONSTRAINT tariff_categories_maximum_amp_check CHECK ((maximum_amp > 0)),
    CONSTRAINT tariff_categories_minimum_amp_check CHECK ((minimum_amp > 0))
);


--
-- Name: telemetries; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.telemetries (
    device_id uuid NOT NULL,
    key_id bigint DEFAULT nextval('bronze.key_id_seq'::regclass) NOT NULL,
    "timestamp" bigint NOT NULL,
    bool boolean,
    dbl double precision,
    "json" json,
    long bigint,
    str character varying(255)
);


--
-- Name: telemetries_dictionaries; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.telemetries_dictionaries (
    id bigint DEFAULT nextval('bronze.id_seq'::regclass) NOT NULL,
    key character varying(400) NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: telemetries_latest; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.telemetries_latest (
    device_id uuid NOT NULL,
    key_id bigint NOT NULL,
    "timestamp" bigint NOT NULL,
    bool boolean,
    dbl double precision,
    "json" json,
    long bigint,
    str character varying(255)
);


--
-- Name: telemetries_notif; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.telemetries_notif (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    device_id uuid NOT NULL,
    key_id bigint NOT NULL,
    "timestamp" bigint NOT NULL,
    bool boolean,
    dbl double precision,
    "json" json,
    long bigint,
    str character varying(255),
    msg character varying(512)
);


--
-- Name: telemetries_notif_users; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.telemetries_notif_users (
    notif_id uuid NOT NULL,
    user_id uuid NOT NULL,
    read boolean NOT NULL,
    read_ts bigint NOT NULL
);


--
-- Name: units; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.units (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    is_building boolean NOT NULL,
    level integer NOT NULL,
    parent_id uuid,
    latitude numeric(10,8),
    longitude numeric(11,8),
    x_coordinate numeric(16,8),
    y_coordinate numeric(16,8),
    type_id uuid NOT NULL,
    active boolean DEFAULT true NOT NULL,
    has_children boolean DEFAULT false NOT NULL,
    icon_id uuid,
    html_hex_color character varying(7),
    description text,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    facility_id uuid NOT NULL,
    CONSTRAINT units_level_check CHECK ((level >= 0))
);


--
-- Name: units_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.units_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    global_type boolean DEFAULT false NOT NULL,
    default_level integer,
    default_type_for_its_level boolean DEFAULT false NOT NULL,
    icon_id uuid,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    facility_id uuid,
    CONSTRAINT units_types_default_level_check CHECK ((default_level >= 0))
);


--
-- Name: upload_batch_items; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.upload_batch_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    batch_id uuid NOT NULL,
    status_id uuid NOT NULL,
    original_filename text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    details json
);


--
-- Name: upload_batches; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.upload_batches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    type_id uuid NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_notified boolean DEFAULT false NOT NULL,
    notified_at timestamp with time zone,
    details json
);


--
-- Name: upload_batches_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.upload_batches_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL
);


--
-- Name: upload_status; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.upload_status (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying(255) NOT NULL,
    first_name character varying(255) NOT NULL,
    last_name character varying(255) NOT NULL,
    password character varying(255) NOT NULL,
    role_id uuid NOT NULL,
    active boolean DEFAULT true,
    mfa_factor_id uuid,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    facility_id uuid,
    mqtt_account_id uuid,
    avatar character varying(255),
    preferences json,
    address_id uuid,
    force_mfa boolean DEFAULT false NOT NULL
);


--
-- Name: water_bill; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_bill (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    water_grid_account_id uuid NOT NULL,
    water_grid_invoice_number character varying(255) NOT NULL,
    grid_period_begin timestamp with time zone NOT NULL,
    grid_period_end timestamp with time zone NOT NULL,
    grid_begin_reading real NOT NULL,
    grid_end_reading real NOT NULL,
    grid_consumption real NOT NULL,
    grid_cost real NOT NULL,
    system_begin_reading real NOT NULL,
    system_end_reading real NOT NULL,
    system_consumption real NOT NULL,
    system_cost real NOT NULL,
    cost_details json NOT NULL,
    consumption_different real NOT NULL,
    created_on timestamp without time zone DEFAULT now(),
    created_by uuid NOT NULL,
    CONSTRAINT water_bill_check CHECK ((grid_end_reading >= grid_begin_reading)),
    CONSTRAINT water_bill_check1 CHECK ((system_end_reading >= system_begin_reading)),
    CONSTRAINT water_bill_grid_begin_reading_check CHECK ((grid_begin_reading >= (0)::double precision)),
    CONSTRAINT water_bill_grid_consumption_check CHECK ((grid_consumption >= (0)::double precision)),
    CONSTRAINT water_bill_grid_cost_check CHECK ((grid_cost >= (0)::double precision)),
    CONSTRAINT water_bill_system_begin_reading_check CHECK ((system_begin_reading >= (0)::double precision)),
    CONSTRAINT water_bill_system_consumption_check CHECK ((system_consumption >= (0)::double precision)),
    CONSTRAINT water_bill_system_cost_check CHECK ((system_cost >= (0)::double precision))
);


--
-- Name: water_bill_water_meter_consume; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_bill_water_meter_consume (
    water_bill_id uuid NOT NULL,
    water_meter_id uuid NOT NULL,
    water_meter_consume real NOT NULL,
    created_on timestamp without time zone DEFAULT now(),
    created_by uuid NOT NULL
);


--
-- Name: water_grid_account; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_grid_account (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    account_number bigint NOT NULL,
    meter_serial_number character varying(255) NOT NULL,
    water_grid_provider_id uuid NOT NULL,
    service_type_id uuid NOT NULL,
    service_class_id uuid NOT NULL,
    start_period timestamp with time zone NOT NULL,
    end_period timestamp with time zone NOT NULL,
    account_cycle_days integer NOT NULL,
    is_new_tariff boolean NOT NULL,
    grid_account_units_count integer NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT water_grid_account_account_cycle_days_check CHECK ((account_cycle_days > 0)),
    CONSTRAINT water_grid_account_grid_account_units_count_check CHECK ((grid_account_units_count > 0))
);


--
-- Name: water_grid_account_global_types; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_grid_account_global_types (
    water_grid_account_id uuid NOT NULL,
    global_type_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now(),
    created_by uuid NOT NULL
);


--
-- Name: water_grid_account_service_class; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_grid_account_service_class (
    id uuid DEFAULT gen_random_uuid() CONSTRAINT water_grid_account_service_class_id_not_null1 NOT NULL,
    name character varying(255) NOT NULL,
    minimal_meter_diameter integer CONSTRAINT water_grid_account_service_clas_minimal_meter_diameter_not_null NOT NULL,
    maximum_meter_diameter integer,
    fee numeric(10,5) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    water_grid_provider_id uuid CONSTRAINT water_grid_account_service_clas_water_grid_provider_id_not_null NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    CONSTRAINT water_grid_account_service_class_fee_check CHECK ((fee > 0.0)),
    CONSTRAINT water_grid_account_service_class_maximum_meter_diameter_check CHECK ((maximum_meter_diameter > 0)),
    CONSTRAINT water_grid_account_service_class_minimal_meter_diameter_check CHECK ((minimal_meter_diameter > 0))
);


--
-- Name: water_grid_account_service_global; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_grid_account_service_global (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    ratio_bill numeric(10,5) NOT NULL,
    water_grid_provider_id uuid CONSTRAINT water_grid_account_service_glob_water_grid_provider_id_not_null NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    CONSTRAINT water_grid_account_service_global_ratio_bill_check CHECK ((ratio_bill > 0.0))
);


--
-- Name: water_grid_account_service_sub_type; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_grid_account_service_sub_type (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    first numeric(10,5) NOT NULL,
    second numeric(10,5) NOT NULL,
    third numeric(10,5) NOT NULL,
    fourth numeric(10,5) NOT NULL,
    above numeric(10,5) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    CONSTRAINT water_grid_account_service_sub_type_above_check CHECK ((above > 0.0)),
    CONSTRAINT water_grid_account_service_sub_type_first_check CHECK ((first > 0.0)),
    CONSTRAINT water_grid_account_service_sub_type_fourth_check CHECK ((fourth > 0.0)),
    CONSTRAINT water_grid_account_service_sub_type_second_check CHECK ((second > 0.0)),
    CONSTRAINT water_grid_account_service_sub_type_third_check CHECK ((third > 0.0))
);


--
-- Name: water_grid_account_service_type; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_grid_account_service_type (
    id uuid DEFAULT gen_random_uuid() CONSTRAINT water_grid_account_service_type_id_not_null1 NOT NULL,
    name character varying(255) NOT NULL,
    c_base numeric(10,5) NOT NULL,
    s1 numeric(10,2) NOT NULL,
    s2 numeric(10,2),
    s3 numeric(10,2),
    s4 numeric(10,2),
    s5 numeric(10,2),
    water_grid_provider_id uuid NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    CONSTRAINT water_grid_account_service_type_c_base_check CHECK ((c_base > 0.0)),
    CONSTRAINT water_grid_account_service_type_check CHECK ((s2 > s1)),
    CONSTRAINT water_grid_account_service_type_check1 CHECK ((s3 > s2)),
    CONSTRAINT water_grid_account_service_type_check2 CHECK ((s4 > s3)),
    CONSTRAINT water_grid_account_service_type_check3 CHECK ((s5 > s4)),
    CONSTRAINT water_grid_account_service_type_s1_check CHECK ((s1 > 0.0))
);


--
-- Name: water_grid_account_units; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_grid_account_units (
    water_grid_account_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now(),
    created_by uuid NOT NULL
);


--
-- Name: water_grid_provider; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_grid_provider (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: water_grid_water_meters; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_grid_water_meters (
    water_grid_account_id uuid NOT NULL,
    water_meter_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now(),
    created_by uuid NOT NULL,
    grid_account_main_meter boolean NOT NULL
);


--
-- Name: water_meter_units; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_meter_units (
    water_meter_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now(),
    created_by uuid NOT NULL,
    unit_main_meter boolean NOT NULL
);


--
-- Name: water_tank; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_tank (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    capacity numeric(10,5) NOT NULL,
    width numeric(10,5) NOT NULL,
    body_height numeric(10,5) NOT NULL,
    inside_water_height numeric(10,5) NOT NULL,
    length numeric(10,5) NOT NULL,
    diameter numeric(10,5),
    thickness numeric(10,5),
    max_temperature numeric(10,5),
    min_temperature numeric(10,5),
    max_pressure numeric(10,5),
    min_pressure numeric(10,5),
    water_source_id uuid NOT NULL,
    type_id uuid NOT NULL,
    location_id uuid NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    label_id uuid,
    CONSTRAINT water_tank_body_height_check CHECK ((body_height > 0.0)),
    CONSTRAINT water_tank_capacity_check CHECK ((capacity > 0.0)),
    CONSTRAINT water_tank_diameter_check CHECK ((diameter > 0.0)),
    CONSTRAINT water_tank_inside_water_height_check CHECK ((inside_water_height > 0.0)),
    CONSTRAINT water_tank_length_check CHECK ((length > 0.0)),
    CONSTRAINT water_tank_thickness_check CHECK ((thickness > 0.0)),
    CONSTRAINT water_tank_width_check CHECK ((width > 0.0))
);


--
-- Name: water_tank_type; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_tank_type (
    id uuid DEFAULT gen_random_uuid() CONSTRAINT water_tank_type_id_not_null1 NOT NULL,
    name character varying(255) NOT NULL,
    created_by uuid NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: water_tank_units; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_tank_units (
    water_tank_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: water_tank_water_sensors; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.water_tank_water_sensors (
    water_tank_id uuid NOT NULL,
    water_sensor_id uuid NOT NULL,
    telemetry_key character varying(400) NOT NULL,
    telemetry_key_id bigint NOT NULL,
    control_id uuid,
    category_name character varying(255) NOT NULL,
    created_on timestamp without time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: migratehistory id; Type: DEFAULT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.migratehistory ALTER COLUMN id SET DEFAULT nextval('bronze.migratehistory_id_seq'::regclass);


--
-- Name: schedule_controllers id; Type: DEFAULT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_controllers ALTER COLUMN id SET DEFAULT nextval('bronze.schedule_controllers_id_seq'::regclass);


--
-- Name: schedule_labels id; Type: DEFAULT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_labels ALTER COLUMN id SET DEFAULT nextval('bronze.schedule_labels_id_seq'::regclass);


--
-- Name: schedule_units id; Type: DEFAULT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_units ALTER COLUMN id SET DEFAULT nextval('bronze.schedule_units_id_seq'::regclass);


--
-- Name: addresses addresses_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.addresses
    ADD CONSTRAINT addresses_pkey PRIMARY KEY (id);


--
-- Name: alarm_acknowledgement_types alarm_acknowledgement_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_acknowledgement_types
    ADD CONSTRAINT alarm_acknowledgement_types_pkey PRIMARY KEY (id);


--
-- Name: alarm_acknowledgements alarm_acknowledgements_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_acknowledgements
    ADD CONSTRAINT alarm_acknowledgements_pkey PRIMARY KEY (id);


--
-- Name: alarm_configurations_history alarm_configurations_history_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_configurations_history
    ADD CONSTRAINT alarm_configurations_history_pkey PRIMARY KEY (id);


--
-- Name: alarm_configurations alarm_configurations_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_configurations
    ADD CONSTRAINT alarm_configurations_pkey PRIMARY KEY (id);


--
-- Name: alarm_contact_groups alarm_contact_groups_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_contact_groups
    ADD CONSTRAINT alarm_contact_groups_pkey PRIMARY KEY (alarm_configuration_id, contact_label_id);


--
-- Name: alarm_contact_methods alarm_contact_methods_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_contact_methods
    ADD CONSTRAINT alarm_contact_methods_pkey PRIMARY KEY (alarm_configuration_id, contact_method_id);


--
-- Name: alarm_contacts alarm_contacts_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_contacts
    ADD CONSTRAINT alarm_contacts_pkey PRIMARY KEY (alarm_configuration_id, contact_id);


--
-- Name: alarm_device_mapping alarm_device_mapping_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_device_mapping
    ADD CONSTRAINT alarm_device_mapping_pkey PRIMARY KEY (alarm_configuration_id, alarm_level_id);


--
-- Name: alarm_device alarm_device_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_device
    ADD CONSTRAINT alarm_device_pkey PRIMARY KEY (alarm_configuration_id, alarm_level_id, device_id);


--
-- Name: alarm_levels alarm_levels_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_levels
    ADD CONSTRAINT alarm_levels_pkey PRIMARY KEY (id);


--
-- Name: alarm_log_types alarm_log_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_log_types
    ADD CONSTRAINT alarm_log_types_pkey PRIMARY KEY (id);


--
-- Name: alarm_logs alarm_logs_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_logs
    ADD CONSTRAINT alarm_logs_pkey PRIMARY KEY (alarm_configuration_id, device_id, "timestamp");


--
-- Name: alarm_notifications alarm_notifications_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_notifications
    ADD CONSTRAINT alarm_notifications_pkey PRIMARY KEY (alarm_configuration_id, notification_id);


--
-- Name: alarm_telemetry_keys alarm_telemetry_keys_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_telemetry_keys
    ADD CONSTRAINT alarm_telemetry_keys_pkey PRIMARY KEY (alarm_configuration_id, telemetry_key_id);


--
-- Name: alarm_types alarm_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_types
    ADD CONSTRAINT alarm_types_pkey PRIMARY KEY (id);


--
-- Name: alarms_severities alarms_severities_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarms_severities
    ADD CONSTRAINT alarms_severities_pkey PRIMARY KEY (id);


--
-- Name: alarms_types alarms_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarms_types
    ADD CONSTRAINT alarms_types_pkey PRIMARY KEY (id);


--
-- Name: appliance_category appliance_category_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.appliance_category
    ADD CONSTRAINT appliance_category_pkey PRIMARY KEY (id);


--
-- Name: appliances appliances_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.appliances
    ADD CONSTRAINT appliances_pkey PRIMARY KEY (id);


--
-- Name: attempted_logins attempted_logins_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.attempted_logins
    ADD CONSTRAINT attempted_logins_pkey PRIMARY KEY (id);


--
-- Name: banned_jtis banned_jtis_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.banned_jtis
    ADD CONSTRAINT banned_jtis_pkey PRIMARY KEY (id);


--
-- Name: budget_types budget_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.budget_types
    ADD CONSTRAINT budget_types_pkey PRIMARY KEY (id);


--
-- Name: budgets budgets_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.budgets
    ADD CONSTRAINT budgets_pkey PRIMARY KEY (facility_id, type_id);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: consumption_categories_grid_billing_accounts_types consumption_categories_grid_billing_accounts_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.consumption_categories_grid_billing_accounts_types
    ADD CONSTRAINT consumption_categories_grid_billing_accounts_types_pkey PRIMARY KEY (consumption_category_id, grid_billing_account_type_id);


--
-- Name: consumption_categories consumption_categories_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.consumption_categories
    ADD CONSTRAINT consumption_categories_pkey PRIMARY KEY (id);


--
-- Name: contact_labels contact_labels_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.contact_labels
    ADD CONSTRAINT contact_labels_pkey PRIMARY KEY (contact_id, label_id);


--
-- Name: contact_method_mapping contact_method_mapping_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.contact_method_mapping
    ADD CONSTRAINT contact_method_mapping_pkey PRIMARY KEY (contact_id, contact_method_id);


--
-- Name: contact_methods contact_methods_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.contact_methods
    ADD CONSTRAINT contact_methods_pkey PRIMARY KEY (id);


--
-- Name: contacts contacts_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (id);


--
-- Name: device_control_labels device_control_labels_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_control_labels
    ADD CONSTRAINT device_control_labels_pkey PRIMARY KEY (device_control_id, label_id);


--
-- Name: device_control_types device_control_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_control_types
    ADD CONSTRAINT device_control_types_pkey PRIMARY KEY (id);


--
-- Name: device_controls device_controls_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_controls
    ADD CONSTRAINT device_controls_pkey PRIMARY KEY (id);


--
-- Name: device_controls_unit_pinned device_controls_unit_pinned_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_controls_unit_pinned
    ADD CONSTRAINT device_controls_unit_pinned_pkey PRIMARY KEY (id);


--
-- Name: device_credentials device_credentials_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_credentials
    ADD CONSTRAINT device_credentials_pkey PRIMARY KEY (cred_id);


--
-- Name: device device_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device
    ADD CONSTRAINT device_pkey PRIMARY KEY (id);


--
-- Name: device_sensors device_sensors_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_sensors
    ADD CONSTRAINT device_sensors_pkey PRIMARY KEY (sensor_id, telemetry_key);


--
-- Name: device_time device_time_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_time
    ADD CONSTRAINT device_time_pkey PRIMARY KEY (device_id, "timestamp");


--
-- Name: devices_categories devices_categories_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.devices_categories
    ADD CONSTRAINT devices_categories_pkey PRIMARY KEY (id);


--
-- Name: devices_types devices_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.devices_types
    ADD CONSTRAINT devices_types_pkey PRIMARY KEY (id);


--
-- Name: energy_bills_tracking energy_bills_tracking_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_bills_tracking
    ADD CONSTRAINT energy_bills_tracking_pkey PRIMARY KEY (id);


--
-- Name: energy_meter_phase_map energy_meter_phase_map_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meter_phase_map
    ADD CONSTRAINT energy_meter_phase_map_pkey PRIMARY KEY (parent_device, phase_parent, child_device, phase_child);


--
-- Name: energy_meters energy_meters_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meters
    ADD CONSTRAINT energy_meters_pkey PRIMARY KEY (id);


--
-- Name: energy_meters_types energy_meters_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meters_types
    ADD CONSTRAINT energy_meters_types_pkey PRIMARY KEY (id);


--
-- Name: energy_saving_recommendations energy_saving_recommendations_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_saving_recommendations
    ADD CONSTRAINT energy_saving_recommendations_pkey PRIMARY KEY (id);


--
-- Name: facilities facilities_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.facilities
    ADD CONSTRAINT facilities_pkey PRIMARY KEY (id);


--
-- Name: facilities_types facilities_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.facilities_types
    ADD CONSTRAINT facilities_types_pkey PRIMARY KEY (id);


--
-- Name: firmwares firmwares_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.firmwares
    ADD CONSTRAINT firmwares_pkey PRIMARY KEY (id);


--
-- Name: floor_plan floor_plan_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.floor_plan
    ADD CONSTRAINT floor_plan_pkey PRIMARY KEY (id);


--
-- Name: forget_password forget_password_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.forget_password
    ADD CONSTRAINT forget_password_pkey PRIMARY KEY (id);


--
-- Name: grid_billing_accounts grid_billing_accounts_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.grid_billing_accounts
    ADD CONSTRAINT grid_billing_accounts_pkey PRIMARY KEY (id);


--
-- Name: grid_billing_accounts_service_classes grid_billing_accounts_service_classes_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.grid_billing_accounts_service_classes
    ADD CONSTRAINT grid_billing_accounts_service_classes_pkey PRIMARY KEY (id);


--
-- Name: grid_billing_accounts_types grid_billing_accounts_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.grid_billing_accounts_types
    ADD CONSTRAINT grid_billing_accounts_types_pkey PRIMARY KEY (id);


--
-- Name: icons icons_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.icons
    ADD CONSTRAINT icons_pkey PRIMARY KEY (id);


--
-- Name: label_types label_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.label_types
    ADD CONSTRAINT label_types_pkey PRIMARY KEY (id);


--
-- Name: labels labels_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.labels
    ADD CONSTRAINT labels_pkey PRIMARY KEY (id);


--
-- Name: migratehistory migratehistory_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.migratehistory
    ADD CONSTRAINT migratehistory_pkey PRIMARY KEY (id);


--
-- Name: modules modules_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.modules
    ADD CONSTRAINT modules_pkey PRIMARY KEY (id);


--
-- Name: mqtt_service_accounts_allowed_topics mqtt_service_accounts_allowed_topics_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.mqtt_service_accounts_allowed_topics
    ADD CONSTRAINT mqtt_service_accounts_allowed_topics_pkey PRIMARY KEY (id);


--
-- Name: mqtt_service_accounts mqtt_service_accounts_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.mqtt_service_accounts
    ADD CONSTRAINT mqtt_service_accounts_pkey PRIMARY KEY (id);


--
-- Name: mqtt_topics mqtt_topics_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.mqtt_topics
    ADD CONSTRAINT mqtt_topics_pkey PRIMARY KEY (id);


--
-- Name: multi_factor_authentication_factors multi_factor_authentication_factors_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.multi_factor_authentication_factors
    ADD CONSTRAINT multi_factor_authentication_factors_pkey PRIMARY KEY (id);


--
-- Name: multi_factor_authentication_types multi_factor_authentication_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.multi_factor_authentication_types
    ADD CONSTRAINT multi_factor_authentication_types_pkey PRIMARY KEY (id);


--
-- Name: notification_types notification_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.notification_types
    ADD CONSTRAINT notification_types_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: overlay_controllers overlay_controllers_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.overlay_controllers
    ADD CONSTRAINT overlay_controllers_pkey PRIMARY KEY (overlay_id, controller_id);


--
-- Name: overlays overlays_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.overlays
    ADD CONSTRAINT overlays_pkey PRIMARY KEY (id);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: role_module_permission role_module_permission_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.role_module_permission
    ADD CONSTRAINT role_module_permission_pkey PRIMARY KEY (role_id, module_id);


--
-- Name: role_units role_units_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.role_units
    ADD CONSTRAINT role_units_pkey PRIMARY KEY (role_id, unit_id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: schedule_controllers schedule_controllers_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_controllers
    ADD CONSTRAINT schedule_controllers_pkey PRIMARY KEY (id);


--
-- Name: schedule_jobs schedule_jobs_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_jobs
    ADD CONSTRAINT schedule_jobs_pkey PRIMARY KEY (job_id);


--
-- Name: schedule_labels schedule_labels_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_labels
    ADD CONSTRAINT schedule_labels_pkey PRIMARY KEY (id);


--
-- Name: schedule_units schedule_units_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_units
    ADD CONSTRAINT schedule_units_pkey PRIMARY KEY (id);


--
-- Name: schedules schedules_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedules
    ADD CONSTRAINT schedules_pkey PRIMARY KEY (id);


--
-- Name: tariff_categories tariff_categories_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.tariff_categories
    ADD CONSTRAINT tariff_categories_pkey PRIMARY KEY (id);


--
-- Name: telemetries_dictionaries telemetries_dictionaries_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.telemetries_dictionaries
    ADD CONSTRAINT telemetries_dictionaries_pkey PRIMARY KEY (id);


--
-- Name: telemetries_latest telemetries_latest_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.telemetries_latest
    ADD CONSTRAINT telemetries_latest_pkey PRIMARY KEY (device_id, key_id);


--
-- Name: telemetries_notif telemetries_notif_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.telemetries_notif
    ADD CONSTRAINT telemetries_notif_pkey PRIMARY KEY (id);


--
-- Name: telemetries_notif_users telemetries_notif_users_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.telemetries_notif_users
    ADD CONSTRAINT telemetries_notif_users_pkey PRIMARY KEY (notif_id, user_id);


--
-- Name: telemetries telemetries_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.telemetries
    ADD CONSTRAINT telemetries_pkey PRIMARY KEY (device_id, key_id, "timestamp");


--
-- Name: device unique_serial_number; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device
    ADD CONSTRAINT unique_serial_number UNIQUE (serial_number);


--
-- Name: device_credentials unique_uudid; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_credentials
    ADD CONSTRAINT unique_uudid UNIQUE (uudid);


--
-- Name: units units_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (id);


--
-- Name: units_types units_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.units_types
    ADD CONSTRAINT units_types_pkey PRIMARY KEY (id);


--
-- Name: upload_batch_items upload_batch_items_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.upload_batch_items
    ADD CONSTRAINT upload_batch_items_pkey PRIMARY KEY (id);


--
-- Name: upload_batches upload_batches_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.upload_batches
    ADD CONSTRAINT upload_batches_pkey PRIMARY KEY (id);


--
-- Name: upload_batches_types upload_batches_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.upload_batches_types
    ADD CONSTRAINT upload_batches_types_pkey PRIMARY KEY (id);


--
-- Name: upload_status upload_status_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.upload_status
    ADD CONSTRAINT upload_status_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: water_bill water_bill_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_bill
    ADD CONSTRAINT water_bill_pkey PRIMARY KEY (id);


--
-- Name: water_bill_water_meter_consume water_bill_water_meter_consume_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_bill_water_meter_consume
    ADD CONSTRAINT water_bill_water_meter_consume_pkey PRIMARY KEY (water_bill_id, water_meter_id);


--
-- Name: water_grid_account_global_types water_grid_account_global_types_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_global_types
    ADD CONSTRAINT water_grid_account_global_types_pkey PRIMARY KEY (water_grid_account_id, global_type_id);


--
-- Name: water_grid_account water_grid_account_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account
    ADD CONSTRAINT water_grid_account_pkey PRIMARY KEY (id);


--
-- Name: water_grid_account_service_class water_grid_account_service_class_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_service_class
    ADD CONSTRAINT water_grid_account_service_class_pkey PRIMARY KEY (id);


--
-- Name: water_grid_account_service_global water_grid_account_service_global_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_service_global
    ADD CONSTRAINT water_grid_account_service_global_pkey PRIMARY KEY (id);


--
-- Name: water_grid_account_service_sub_type water_grid_account_service_sub_type_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_service_sub_type
    ADD CONSTRAINT water_grid_account_service_sub_type_pkey PRIMARY KEY (id);


--
-- Name: water_grid_account_service_type water_grid_account_service_type_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_service_type
    ADD CONSTRAINT water_grid_account_service_type_pkey PRIMARY KEY (id);


--
-- Name: water_grid_account_units water_grid_account_units_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_units
    ADD CONSTRAINT water_grid_account_units_pkey PRIMARY KEY (water_grid_account_id, unit_id);


--
-- Name: water_grid_provider water_grid_provider_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_provider
    ADD CONSTRAINT water_grid_provider_pkey PRIMARY KEY (id);


--
-- Name: water_grid_water_meters water_grid_water_meters_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_water_meters
    ADD CONSTRAINT water_grid_water_meters_pkey PRIMARY KEY (water_grid_account_id, water_meter_id);


--
-- Name: water_meter_units water_meter_units_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_meter_units
    ADD CONSTRAINT water_meter_units_pkey PRIMARY KEY (unit_id, water_meter_id);


--
-- Name: water_tank water_tank_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank
    ADD CONSTRAINT water_tank_pkey PRIMARY KEY (id);


--
-- Name: water_tank_type water_tank_type_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_type
    ADD CONSTRAINT water_tank_type_pkey PRIMARY KEY (id);


--
-- Name: water_tank_units water_tank_units_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_units
    ADD CONSTRAINT water_tank_units_pkey PRIMARY KEY (water_tank_id, unit_id);


--
-- Name: water_tank_water_sensors water_tank_water_sensors_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_water_sensors
    ADD CONSTRAINT water_tank_water_sensors_pkey PRIMARY KEY (water_sensor_id, telemetry_key);


--
-- Name: addresses_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX addresses_created_by ON bronze.addresses USING btree (created_by);


--
-- Name: addresses_title; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX addresses_title ON bronze.addresses USING btree (title);


--
-- Name: alarmacknowledgement_acknowledged_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmacknowledgement_acknowledged_by ON bronze.alarm_acknowledgements USING btree (acknowledged_by);


--
-- Name: alarmacknowledgement_alarm_configuration_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmacknowledgement_alarm_configuration_id ON bronze.alarm_acknowledgements USING btree (alarm_configuration_id);


--
-- Name: alarmacknowledgement_device_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmacknowledgement_device_id ON bronze.alarm_acknowledgements USING btree (device_id);


--
-- Name: alarmconfiguration_alarm_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmconfiguration_alarm_type_id ON bronze.alarm_configurations USING btree (alarm_type_id);


--
-- Name: alarmconfiguration_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmconfiguration_created_by ON bronze.alarm_configurations USING btree (created_by);


--
-- Name: alarmconfiguration_severity_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmconfiguration_severity_id ON bronze.alarm_configurations USING btree (severity_id);


--
-- Name: alarmconfigurationhistory_alarm_configuration_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmconfigurationhistory_alarm_configuration_id ON bronze.alarm_configurations_history USING btree (alarm_configuration_id);


--
-- Name: alarmconfigurationhistory_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmconfigurationhistory_created_by ON bronze.alarm_configurations_history USING btree (created_by);


--
-- Name: alarmconfigurationhistory_updated_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmconfigurationhistory_updated_by ON bronze.alarm_configurations_history USING btree (updated_by);


--
-- Name: alarmcontact_alarm_configuration_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmcontact_alarm_configuration_id ON bronze.alarm_contacts USING btree (alarm_configuration_id);


--
-- Name: alarmcontact_contact_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmcontact_contact_id ON bronze.alarm_contacts USING btree (contact_id);


--
-- Name: alarmcontactgroup_alarm_configuration_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmcontactgroup_alarm_configuration_id ON bronze.alarm_contact_groups USING btree (alarm_configuration_id);


--
-- Name: alarmcontactgroup_contact_label_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmcontactgroup_contact_label_id ON bronze.alarm_contact_groups USING btree (contact_label_id);


--
-- Name: alarmcontactmethod_alarm_configuration_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmcontactmethod_alarm_configuration_id ON bronze.alarm_contact_methods USING btree (alarm_configuration_id);


--
-- Name: alarmcontactmethod_contact_method_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmcontactmethod_contact_method_id ON bronze.alarm_contact_methods USING btree (contact_method_id);


--
-- Name: alarmdevice_alarm_configuration_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmdevice_alarm_configuration_id ON bronze.alarm_device USING btree (alarm_configuration_id);


--
-- Name: alarmdevice_alarm_level_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmdevice_alarm_level_id ON bronze.alarm_device USING btree (alarm_level_id);


--
-- Name: alarmdevice_device_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmdevice_device_id ON bronze.alarm_device USING btree (device_id);


--
-- Name: alarmdevicemapping_alarm_configuration_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmdevicemapping_alarm_configuration_id ON bronze.alarm_device_mapping USING btree (alarm_configuration_id);


--
-- Name: alarmdevicemapping_alarm_level_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmdevicemapping_alarm_level_id ON bronze.alarm_device_mapping USING btree (alarm_level_id);


--
-- Name: alarmdevicemapping_device_category_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmdevicemapping_device_category_id ON bronze.alarm_device_mapping USING btree (device_category_id);


--
-- Name: alarmdevicemapping_device_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmdevicemapping_device_type_id ON bronze.alarm_device_mapping USING btree (device_type_id);


--
-- Name: alarmdevicemapping_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmdevicemapping_unit_id ON bronze.alarm_device_mapping USING btree (unit_id);


--
-- Name: alarmlevel_title; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX alarmlevel_title ON bronze.alarm_levels USING btree (title);


--
-- Name: alarmlog_alarm_configuration_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmlog_alarm_configuration_id ON bronze.alarm_logs USING btree (alarm_configuration_id);


--
-- Name: alarmlog_device_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmlog_device_id ON bronze.alarm_logs USING btree (device_id);


--
-- Name: alarmlog_log_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmlog_log_type_id ON bronze.alarm_logs USING btree (log_type_id);


--
-- Name: alarmnotification_alarm_configuration_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmnotification_alarm_configuration_id ON bronze.alarm_notifications USING btree (alarm_configuration_id);


--
-- Name: alarmnotification_device_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmnotification_device_id ON bronze.alarm_notifications USING btree (device_id);


--
-- Name: alarmnotification_notification_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmnotification_notification_id ON bronze.alarm_notifications USING btree (notification_id);


--
-- Name: alarmseverity_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmseverity_created_by ON bronze.alarms_severities USING btree (created_by);


--
-- Name: alarmseverity_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX alarmseverity_name ON bronze.alarms_severities USING btree (name);


--
-- Name: alarmtelemetrykey_alarm_configuration_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmtelemetrykey_alarm_configuration_id ON bronze.alarm_telemetry_keys USING btree (alarm_configuration_id);


--
-- Name: alarmtelemetrykey_telemetry_key_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX alarmtelemetrykey_telemetry_key_id ON bronze.alarm_telemetry_keys USING btree (telemetry_key_id);


--
-- Name: alarmtype_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX alarmtype_name ON bronze.alarms_types USING btree (name);


--
-- Name: alarmtype_title; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX alarmtype_title ON bronze.alarm_types USING btree (title);


--
-- Name: appliance_category_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX appliance_category_id ON bronze.appliances USING btree (category_id);


--
-- Name: appliance_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX appliance_created_by ON bronze.appliances USING btree (created_by);


--
-- Name: appliance_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX appliance_facility_id ON bronze.appliances USING btree (facility_id);


--
-- Name: appliance_meter_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX appliance_meter_id ON bronze.appliances USING btree (meter_id);


--
-- Name: appliance_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX appliance_unit_id ON bronze.appliances USING btree (unit_id);


--
-- Name: attemptedlogin_user_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX attemptedlogin_user_id ON bronze.attempted_logins USING btree (user_id);


--
-- Name: bannedjtis_user_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX bannedjtis_user_id ON bronze.banned_jtis USING btree (user_id);


--
-- Name: budget_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX budget_created_by ON bronze.budgets USING btree (created_by);


--
-- Name: budget_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX budget_facility_id ON bronze.budgets USING btree (facility_id);


--
-- Name: budget_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX budget_type_id ON bronze.budgets USING btree (type_id);


--
-- Name: client_code; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX client_code ON bronze.clients USING btree (code);


--
-- Name: client_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX client_facility_id ON bronze.clients USING btree (facility_id);


--
-- Name: consumptioncategoriesgridbillingaccounttype_consumption__351250; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX consumptioncategoriesgridbillingaccounttype_consumption__351250 ON bronze.consumption_categories_grid_billing_accounts_types USING btree (consumption_category_id, grid_billing_account_type_id);


--
-- Name: consumptioncategoriesgridbillingaccounttype_consumption__e16f0e; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX consumptioncategoriesgridbillingaccounttype_consumption__e16f0e ON bronze.consumption_categories_grid_billing_accounts_types USING btree (consumption_category_id);


--
-- Name: consumptioncategoriesgridbillingaccounttype_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX consumptioncategoriesgridbillingaccounttype_created_by ON bronze.consumption_categories_grid_billing_accounts_types USING btree (created_by);


--
-- Name: consumptioncategoriesgridbillingaccounttype_grid_billing_adda13; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX consumptioncategoriesgridbillingaccounttype_grid_billing_adda13 ON bronze.consumption_categories_grid_billing_accounts_types USING btree (grid_billing_account_type_id);


--
-- Name: consumptioncategory_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX consumptioncategory_created_by ON bronze.consumption_categories USING btree (created_by);


--
-- Name: consumptioncategory_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX consumptioncategory_facility_id ON bronze.consumption_categories USING btree (facility_id);


--
-- Name: contact_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX contact_created_by ON bronze.contacts USING btree (created_by);


--
-- Name: contact_email; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX contact_email ON bronze.contacts USING btree (email);


--
-- Name: contact_phone_number; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX contact_phone_number ON bronze.contacts USING btree (phone_number);


--
-- Name: contact_user_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX contact_user_id ON bronze.contacts USING btree (user_id);


--
-- Name: contactlabel_contact_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX contactlabel_contact_id ON bronze.contact_labels USING btree (contact_id);


--
-- Name: contactlabel_label_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX contactlabel_label_id ON bronze.contact_labels USING btree (label_id);


--
-- Name: contactmethod_title; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX contactmethod_title ON bronze.contact_methods USING btree (title);


--
-- Name: contactmethodmapping_contact_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX contactmethodmapping_contact_id ON bronze.contact_method_mapping USING btree (contact_id);


--
-- Name: contactmethodmapping_contact_method_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX contactmethodmapping_contact_method_id ON bronze.contact_method_mapping USING btree (contact_method_id);


--
-- Name: device_client_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX device_client_id ON bronze.device USING btree (client_id);


--
-- Name: device_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX device_created_by ON bronze.device USING btree (created_by);


--
-- Name: device_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX device_facility_id ON bronze.device USING btree (facility_id);


--
-- Name: device_gateway_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX device_gateway_id ON bronze.device USING btree (gateway_id);


--
-- Name: device_label; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX device_label ON bronze.device USING btree (label);


--
-- Name: device_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX device_name ON bronze.device USING btree (name);


--
-- Name: device_properties; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX device_properties ON bronze.device USING gin (properties);


--
-- Name: device_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX device_type_id ON bronze.device USING btree (type_id);


--
-- Name: device_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX device_unit_id ON bronze.device USING btree (unit_id);


--
-- Name: devicecategories_code; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX devicecategories_code ON bronze.devices_categories USING btree (code);


--
-- Name: devicecategories_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX devicecategories_name ON bronze.devices_categories USING btree (name);


--
-- Name: devicecontrollabel_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicecontrollabel_created_by ON bronze.device_control_labels USING btree (created_by);


--
-- Name: devicecontrollabel_device_control_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicecontrollabel_device_control_id ON bronze.device_control_labels USING btree (device_control_id);


--
-- Name: devicecontrollabel_label_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicecontrollabel_label_id ON bronze.device_control_labels USING btree (label_id);


--
-- Name: devicecontrols_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicecontrols_created_by ON bronze.device_controls USING btree (created_by);


--
-- Name: devicecontrols_device_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicecontrols_device_id ON bronze.device_controls USING btree (device_id);


--
-- Name: devicecontrols_name_device_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX devicecontrols_name_device_id ON bronze.device_controls USING btree (name, device_id);


--
-- Name: devicecontrols_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicecontrols_unit_id ON bronze.device_controls USING btree (unit_id);


--
-- Name: devicecontrolsunitpinned_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicecontrolsunitpinned_unit_id ON bronze.device_controls_unit_pinned USING btree (unit_id);


--
-- Name: devicecontrolsunitpinned_user_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicecontrolsunitpinned_user_id ON bronze.device_controls_unit_pinned USING btree (user_id);


--
-- Name: devicecontroltypes_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX devicecontroltypes_name ON bronze.device_control_types USING btree (name);


--
-- Name: devicecredentials_device_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX devicecredentials_device_id ON bronze.device_credentials USING btree (device_id);


--
-- Name: devices_types_properties; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devices_types_properties ON bronze.devices_types USING gin (properties);


--
-- Name: devicesensors_category_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicesensors_category_name ON bronze.device_sensors USING btree (category_name);


--
-- Name: devicesensors_control_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicesensors_control_id ON bronze.device_sensors USING btree (control_id);


--
-- Name: devicesensors_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicesensors_created_by ON bronze.device_sensors USING btree (created_by);


--
-- Name: devicesensors_device_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicesensors_device_id ON bronze.device_sensors USING btree (device_id);


--
-- Name: devicesensors_device_id_sensor_id_telemetry_key_category_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX devicesensors_device_id_sensor_id_telemetry_key_category_name ON bronze.device_sensors USING btree (device_id, sensor_id, telemetry_key, category_name);


--
-- Name: devicesensors_sensor_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicesensors_sensor_id ON bronze.device_sensors USING btree (sensor_id);


--
-- Name: devicesensors_telemetry_key; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicesensors_telemetry_key ON bronze.device_sensors USING btree (telemetry_key);


--
-- Name: devicesensors_telemetry_key_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicesensors_telemetry_key_id ON bronze.device_sensors USING btree (telemetry_key_id);


--
-- Name: devicetime_device_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicetime_device_id ON bronze.device_time USING btree (device_id);


--
-- Name: devicetime_telemetry_key_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicetime_telemetry_key_name ON bronze.device_time USING btree (telemetry_key_name);


--
-- Name: devicetypes_category_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicetypes_category_id ON bronze.devices_types USING btree (category_id);


--
-- Name: devicetypes_category_id_code; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX devicetypes_category_id_code ON bronze.devices_types USING btree (category_id, code);


--
-- Name: devicetypes_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX devicetypes_created_by ON bronze.devices_types USING btree (created_by);


--
-- Name: devicetypes_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX devicetypes_name ON bronze.devices_types USING btree (name);


--
-- Name: energy_bills_tracking_invoice_number; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX energy_bills_tracking_invoice_number ON bronze.energy_bills_tracking USING btree (invoice_number);


--
-- Name: energybilltracking_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energybilltracking_created_by ON bronze.energy_bills_tracking USING btree (created_by);


--
-- Name: energybilltracking_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energybilltracking_facility_id ON bronze.energy_bills_tracking USING btree (facility_id);


--
-- Name: energybilltracking_grid_billing_account_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energybilltracking_grid_billing_account_id ON bronze.energy_bills_tracking USING btree (grid_billing_account_id);


--
-- Name: energymeter_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energymeter_created_by ON bronze.energy_meters USING btree (created_by);


--
-- Name: energymeter_device_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energymeter_device_id ON bronze.energy_meters USING btree (device_id);


--
-- Name: energymeter_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energymeter_facility_id ON bronze.energy_meters USING btree (facility_id);


--
-- Name: energymeter_grid_billing_account_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energymeter_grid_billing_account_id ON bronze.energy_meters USING btree (grid_billing_account_id);


--
-- Name: energymeter_parent_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energymeter_parent_id ON bronze.energy_meters USING btree (parent_id);


--
-- Name: energymeter_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energymeter_type_id ON bronze.energy_meters USING btree (type_id);


--
-- Name: energymeter_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energymeter_unit_id ON bronze.energy_meters USING btree (unit_id);


--
-- Name: energymeterphasemap_child_device; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energymeterphasemap_child_device ON bronze.energy_meter_phase_map USING btree (child_device);


--
-- Name: energymeterphasemap_parent_device; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energymeterphasemap_parent_device ON bronze.energy_meter_phase_map USING btree (parent_device);


--
-- Name: energymetertype_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX energymetertype_name ON bronze.energy_meters_types USING btree (name);


--
-- Name: energysavingrecommendation_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX energysavingrecommendation_facility_id ON bronze.energy_saving_recommendations USING btree (facility_id);


--
-- Name: facilities_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX facilities_created_by ON bronze.facilities USING btree (created_by);


--
-- Name: facilities_types_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX facilities_types_created_by ON bronze.facilities_types USING btree (created_by);


--
-- Name: facility_address_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX facility_address_id ON bronze.facilities USING btree (address_id);


--
-- Name: facility_facility_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX facility_facility_type_id ON bronze.facilities USING btree (facility_type_id);


--
-- Name: facility_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX facility_name ON bronze.facilities USING btree (name);


--
-- Name: facility_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX facility_unit_id ON bronze.facilities USING btree (unit_id);


--
-- Name: facilitytypes_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX facilitytypes_name ON bronze.facilities_types USING btree (name);


--
-- Name: firmware_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX firmware_created_by ON bronze.firmwares USING btree (created_by);


--
-- Name: firmware_filename; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX firmware_filename ON bronze.firmwares USING btree (filename);


--
-- Name: floorplan_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX floorplan_created_by ON bronze.floor_plan USING btree (created_by);


--
-- Name: floorplan_image_proprties; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX floorplan_image_proprties ON bronze.floor_plan USING gin (image_proprties);


--
-- Name: floorplan_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX floorplan_unit_id ON bronze.floor_plan USING btree (unit_id);


--
-- Name: forgetpassword_user_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX forgetpassword_user_id ON bronze.forget_password USING btree (user_id);


--
-- Name: gridbillingaccount_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX gridbillingaccount_created_by ON bronze.grid_billing_accounts USING btree (created_by);


--
-- Name: gridbillingaccount_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX gridbillingaccount_facility_id ON bronze.grid_billing_accounts USING btree (facility_id);


--
-- Name: gridbillingaccount_label; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX gridbillingaccount_label ON bronze.grid_billing_accounts USING btree (label);


--
-- Name: gridbillingaccount_meter_serial_number; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX gridbillingaccount_meter_serial_number ON bronze.grid_billing_accounts USING btree (meter_serial_number);


--
-- Name: gridbillingaccount_number; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX gridbillingaccount_number ON bronze.grid_billing_accounts USING btree (number);


--
-- Name: gridbillingaccount_service_class_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX gridbillingaccount_service_class_id ON bronze.grid_billing_accounts USING btree (service_class_id);


--
-- Name: gridbillingaccount_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX gridbillingaccount_type_id ON bronze.grid_billing_accounts USING btree (type_id);


--
-- Name: gridbillingaccount_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX gridbillingaccount_unit_id ON bronze.grid_billing_accounts USING btree (unit_id);


--
-- Name: gridbillingaccountserviceclass_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX gridbillingaccountserviceclass_created_by ON bronze.grid_billing_accounts_service_classes USING btree (created_by);


--
-- Name: gridbillingaccountserviceclass_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX gridbillingaccountserviceclass_facility_id ON bronze.grid_billing_accounts_service_classes USING btree (facility_id);


--
-- Name: gridbillingaccountserviceclass_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX gridbillingaccountserviceclass_name ON bronze.grid_billing_accounts_service_classes USING btree (name);


--
-- Name: gridbillingaccounttypes_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX gridbillingaccounttypes_name ON bronze.grid_billing_accounts_types USING btree (name);


--
-- Name: icon_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX icon_name ON bronze.icons USING btree (name);


--
-- Name: labels_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX labels_created_by ON bronze.labels USING btree (created_by);


--
-- Name: labels_label_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX labels_label_type_id ON bronze.labels USING btree (label_type_id);


--
-- Name: labels_name_label_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX labels_name_label_type_id ON bronze.labels USING btree (name, label_type_id);


--
-- Name: labeltypes_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX labeltypes_created_by ON bronze.label_types USING btree (created_by);


--
-- Name: labeltypes_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX labeltypes_name ON bronze.label_types USING btree (name);


--
-- Name: modules_parent_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX modules_parent_id ON bronze.modules USING btree (parent_id);


--
-- Name: modules_title; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX modules_title ON bronze.modules USING btree (title);


--
-- Name: mqttserviceaccount_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX mqttserviceaccount_created_by ON bronze.mqtt_service_accounts USING btree (created_by);


--
-- Name: mqttserviceaccount_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX mqttserviceaccount_facility_id ON bronze.mqtt_service_accounts USING btree (facility_id);


--
-- Name: mqttserviceaccount_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX mqttserviceaccount_name ON bronze.mqtt_service_accounts USING btree (name);


--
-- Name: mqttserviceaccount_username_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX mqttserviceaccount_username_facility_id ON bronze.mqtt_service_accounts USING btree (username, facility_id);


--
-- Name: mqttserviceaccountallowedtopic_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX mqttserviceaccountallowedtopic_created_by ON bronze.mqtt_service_accounts_allowed_topics USING btree (created_by);


--
-- Name: mqttserviceaccountallowedtopic_mqtt_service_account_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX mqttserviceaccountallowedtopic_mqtt_service_account_id ON bronze.mqtt_service_accounts_allowed_topics USING btree (mqtt_service_account_id);


--
-- Name: mqttserviceaccountallowedtopic_mqtt_topic_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX mqttserviceaccountallowedtopic_mqtt_topic_id ON bronze.mqtt_service_accounts_allowed_topics USING btree (mqtt_topic_id);


--
-- Name: mqtttopic_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX mqtttopic_facility_id ON bronze.mqtt_topics USING btree (facility_id);


--
-- Name: mqtttopic_topic; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX mqtttopic_topic ON bronze.mqtt_topics USING btree (topic);


--
-- Name: multifactorauthenticationfactor_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX multifactorauthenticationfactor_type_id ON bronze.multi_factor_authentication_factors USING btree (type_id);


--
-- Name: multifactorauthenticationtype_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX multifactorauthenticationtype_name ON bronze.multi_factor_authentication_types USING btree (name);


--
-- Name: notification_contact_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX notification_contact_id ON bronze.notifications USING btree (contact_id);


--
-- Name: notification_contact_method_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX notification_contact_method_id ON bronze.notifications USING btree (contact_method_id);


--
-- Name: notification_notification_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX notification_notification_type_id ON bronze.notifications USING btree (notification_type_id);


--
-- Name: overlaycontrollers_controller_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX overlaycontrollers_controller_id ON bronze.overlay_controllers USING btree (controller_id);


--
-- Name: overlaycontrollers_overlay_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX overlaycontrollers_overlay_id ON bronze.overlay_controllers USING btree (overlay_id);


--
-- Name: overlays_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX overlays_created_by ON bronze.overlays USING btree (created_by);


--
-- Name: overlays_floor_plan_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX overlays_floor_plan_id ON bronze.overlays USING btree (floor_plan_id);


--
-- Name: overlays_floor_plan_id_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX overlays_floor_plan_id_name ON bronze.overlays USING btree (floor_plan_id, name);


--
-- Name: overlays_shape_config; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX overlays_shape_config ON bronze.overlays USING gin (shape_config);


--
-- Name: overlays_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX overlays_unit_id ON bronze.overlays USING btree (unit_id);


--
-- Name: permission_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX permission_created_by ON bronze.permissions USING btree (created_by);


--
-- Name: permission_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX permission_name ON bronze.permissions USING btree (name);


--
-- Name: rolemodulepermission_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX rolemodulepermission_created_by ON bronze.role_module_permission USING btree (created_by);


--
-- Name: rolemodulepermission_module_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX rolemodulepermission_module_id ON bronze.role_module_permission USING btree (module_id);


--
-- Name: rolemodulepermission_permission_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX rolemodulepermission_permission_id ON bronze.role_module_permission USING btree (permission_id);


--
-- Name: rolemodulepermission_role_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX rolemodulepermission_role_id ON bronze.role_module_permission USING btree (role_id);


--
-- Name: roles_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX roles_created_by ON bronze.roles USING btree (created_by);


--
-- Name: roles_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX roles_facility_id ON bronze.roles USING btree (facility_id);


--
-- Name: roleunits_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX roleunits_created_by ON bronze.role_units USING btree (created_by);


--
-- Name: roleunits_role_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX roleunits_role_id ON bronze.role_units USING btree (role_id);


--
-- Name: roleunits_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX roleunits_unit_id ON bronze.role_units USING btree (unit_id);


--
-- Name: schedulecontrollers_controller_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX schedulecontrollers_controller_id ON bronze.schedule_controllers USING btree (controller_id);


--
-- Name: schedulecontrollers_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX schedulecontrollers_created_by ON bronze.schedule_controllers USING btree (created_by);


--
-- Name: schedulecontrollers_schedule_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX schedulecontrollers_schedule_id ON bronze.schedule_controllers USING btree (schedule_id);


--
-- Name: schedulejob_schedule_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX schedulejob_schedule_id ON bronze.schedule_jobs USING btree (schedule_id);


--
-- Name: schedulelabels_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX schedulelabels_created_by ON bronze.schedule_labels USING btree (created_by);


--
-- Name: schedulelabels_label_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX schedulelabels_label_id ON bronze.schedule_labels USING btree (label_id);


--
-- Name: schedulelabels_schedule_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX schedulelabels_schedule_id ON bronze.schedule_labels USING btree (schedule_id);


--
-- Name: schedules_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX schedules_created_by ON bronze.schedules USING btree (created_by);


--
-- Name: schedules_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX schedules_name ON bronze.schedules USING btree (name);


--
-- Name: schedules_triggers; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX schedules_triggers ON bronze.schedules USING gin (triggers);


--
-- Name: scheduleunits_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX scheduleunits_created_by ON bronze.schedule_units USING btree (created_by);


--
-- Name: scheduleunits_schedule_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX scheduleunits_schedule_id ON bronze.schedule_units USING btree (schedule_id);


--
-- Name: scheduleunits_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX scheduleunits_unit_id ON bronze.schedule_units USING btree (unit_id);


--
-- Name: tariffcategory_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX tariffcategory_created_by ON bronze.tariff_categories USING btree (created_by);


--
-- Name: tariffcategory_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX tariffcategory_facility_id ON bronze.tariff_categories USING btree (facility_id);


--
-- Name: tariffcategory_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX tariffcategory_name ON bronze.tariff_categories USING btree (name);


--
-- Name: telemetriesnotif_device_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX telemetriesnotif_device_id ON bronze.telemetries_notif USING btree (device_id);


--
-- Name: telemetriesnotifusers_notif_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX telemetriesnotifusers_notif_id ON bronze.telemetries_notif_users USING btree (notif_id);


--
-- Name: telemetriesnotifusers_notif_id_user_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX telemetriesnotifusers_notif_id_user_id ON bronze.telemetries_notif_users USING btree (notif_id, user_id);


--
-- Name: telemetriesnotifusers_user_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX telemetriesnotifusers_user_id ON bronze.telemetries_notif_users USING btree (user_id);


--
-- Name: telemetrydictionaries_key; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX telemetrydictionaries_key ON bronze.telemetries_dictionaries USING btree (key);


--
-- Name: unit_icon_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX unit_icon_id ON bronze.units USING btree (icon_id);


--
-- Name: unit_level; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX unit_level ON bronze.units USING btree (level);


--
-- Name: unit_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX unit_name ON bronze.units USING btree (name);


--
-- Name: unit_parent_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX unit_parent_id ON bronze.units USING btree (parent_id);


--
-- Name: unit_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX unit_type_id ON bronze.units USING btree (type_id);


--
-- Name: units_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX units_created_by ON bronze.units USING btree (created_by);


--
-- Name: units_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX units_facility_id ON bronze.units USING btree (facility_id);


--
-- Name: units_types_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX units_types_created_by ON bronze.units_types USING btree (created_by);


--
-- Name: units_types_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX units_types_facility_id ON bronze.units_types USING btree (facility_id);


--
-- Name: unittypes_icon_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX unittypes_icon_id ON bronze.units_types USING btree (icon_id);


--
-- Name: unittypes_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX unittypes_name ON bronze.units_types USING btree (name);


--
-- Name: uploadbatch_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX uploadbatch_created_by ON bronze.upload_batches USING btree (created_by);


--
-- Name: uploadbatch_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX uploadbatch_type_id ON bronze.upload_batches USING btree (type_id);


--
-- Name: uploadbatchitem_batch_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX uploadbatchitem_batch_id ON bronze.upload_batch_items USING btree (batch_id);


--
-- Name: uploadbatchitem_status_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX uploadbatchitem_status_id ON bronze.upload_batch_items USING btree (status_id);


--
-- Name: user_email; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX user_email ON bronze.users USING btree (email);


--
-- Name: user_mfa_factor_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX user_mfa_factor_id ON bronze.users USING btree (mfa_factor_id);


--
-- Name: user_role_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX user_role_id ON bronze.users USING btree (role_id);


--
-- Name: users_address_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX users_address_id ON bronze.users USING btree (address_id);


--
-- Name: users_facility_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX users_facility_id ON bronze.users USING btree (facility_id);


--
-- Name: users_mqtt_account_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX users_mqtt_account_id ON bronze.users USING btree (mqtt_account_id);


--
-- Name: waterbill_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX waterbill_created_by ON bronze.water_bill USING btree (created_by);


--
-- Name: waterbill_water_grid_account_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX waterbill_water_grid_account_id ON bronze.water_bill USING btree (water_grid_account_id);


--
-- Name: waterbill_water_grid_invoice_number; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX waterbill_water_grid_invoice_number ON bronze.water_bill USING btree (water_grid_invoice_number);


--
-- Name: waterbillwatermeterconsume_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX waterbillwatermeterconsume_created_by ON bronze.water_bill_water_meter_consume USING btree (created_by);


--
-- Name: waterbillwatermeterconsume_water_bill_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX waterbillwatermeterconsume_water_bill_id ON bronze.water_bill_water_meter_consume USING btree (water_bill_id);


--
-- Name: waterbillwatermeterconsume_water_bill_id_water_meter_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX waterbillwatermeterconsume_water_bill_id_water_meter_id ON bronze.water_bill_water_meter_consume USING btree (water_bill_id, water_meter_id);


--
-- Name: waterbillwatermeterconsume_water_meter_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX waterbillwatermeterconsume_water_meter_id ON bronze.water_bill_water_meter_consume USING btree (water_meter_id);


--
-- Name: watergridaccount_account_number; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watergridaccount_account_number ON bronze.water_grid_account USING btree (account_number);


--
-- Name: watergridaccount_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccount_created_by ON bronze.water_grid_account USING btree (created_by);


--
-- Name: watergridaccount_meter_serial_number; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watergridaccount_meter_serial_number ON bronze.water_grid_account USING btree (meter_serial_number);


--
-- Name: watergridaccount_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watergridaccount_name ON bronze.water_grid_account USING btree (name);


--
-- Name: watergridaccount_service_class_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccount_service_class_id ON bronze.water_grid_account USING btree (service_class_id);


--
-- Name: watergridaccount_service_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccount_service_type_id ON bronze.water_grid_account USING btree (service_type_id);


--
-- Name: watergridaccount_water_grid_provider_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccount_water_grid_provider_id ON bronze.water_grid_account USING btree (water_grid_provider_id);


--
-- Name: watergridaccountglobals_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccountglobals_created_by ON bronze.water_grid_account_global_types USING btree (created_by);


--
-- Name: watergridaccountglobals_global_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccountglobals_global_type_id ON bronze.water_grid_account_global_types USING btree (global_type_id);


--
-- Name: watergridaccountglobals_water_grid_account_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccountglobals_water_grid_account_id ON bronze.water_grid_account_global_types USING btree (water_grid_account_id);


--
-- Name: watergridaccountglobals_water_grid_account_id_global_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watergridaccountglobals_water_grid_account_id_global_type_id ON bronze.water_grid_account_global_types USING btree (water_grid_account_id, global_type_id);


--
-- Name: watergridaccountserviceclass_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccountserviceclass_created_by ON bronze.water_grid_account_service_class USING btree (created_by);


--
-- Name: watergridaccountserviceclass_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watergridaccountserviceclass_name ON bronze.water_grid_account_service_class USING btree (name);


--
-- Name: watergridaccountserviceclass_water_grid_provider_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccountserviceclass_water_grid_provider_id ON bronze.water_grid_account_service_class USING btree (water_grid_provider_id);


--
-- Name: watergridaccountserviceglobal_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccountserviceglobal_created_by ON bronze.water_grid_account_service_global USING btree (created_by);


--
-- Name: watergridaccountserviceglobal_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watergridaccountserviceglobal_name ON bronze.water_grid_account_service_global USING btree (name);


--
-- Name: watergridaccountserviceglobal_water_grid_provider_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccountserviceglobal_water_grid_provider_id ON bronze.water_grid_account_service_global USING btree (water_grid_provider_id);


--
-- Name: watergridaccountservicesubtype_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccountservicesubtype_created_by ON bronze.water_grid_account_service_sub_type USING btree (created_by);


--
-- Name: watergridaccountservicesubtype_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watergridaccountservicesubtype_name ON bronze.water_grid_account_service_sub_type USING btree (name);


--
-- Name: watergridaccountservicetype_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccountservicetype_created_by ON bronze.water_grid_account_service_type USING btree (created_by);


--
-- Name: watergridaccountservicetype_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watergridaccountservicetype_name ON bronze.water_grid_account_service_type USING btree (name);


--
-- Name: watergridaccountservicetype_water_grid_provider_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridaccountservicetype_water_grid_provider_id ON bronze.water_grid_account_service_type USING btree (water_grid_provider_id);


--
-- Name: watergridprovider_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridprovider_created_by ON bronze.water_grid_provider USING btree (created_by);


--
-- Name: watergridprovider_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watergridprovider_name ON bronze.water_grid_provider USING btree (name);


--
-- Name: watergridunits_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridunits_created_by ON bronze.water_grid_account_units USING btree (created_by);


--
-- Name: watergridunits_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridunits_unit_id ON bronze.water_grid_account_units USING btree (unit_id);


--
-- Name: watergridunits_water_grid_account_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridunits_water_grid_account_id ON bronze.water_grid_account_units USING btree (water_grid_account_id);


--
-- Name: watergridunits_water_grid_account_id_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watergridunits_water_grid_account_id_unit_id ON bronze.water_grid_account_units USING btree (water_grid_account_id, unit_id);


--
-- Name: watergridwatermeters_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridwatermeters_created_by ON bronze.water_grid_water_meters USING btree (created_by);


--
-- Name: watergridwatermeters_water_grid_account_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridwatermeters_water_grid_account_id ON bronze.water_grid_water_meters USING btree (water_grid_account_id);


--
-- Name: watergridwatermeters_water_grid_account_id_water_meter_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watergridwatermeters_water_grid_account_id_water_meter_id ON bronze.water_grid_water_meters USING btree (water_grid_account_id, water_meter_id);


--
-- Name: watergridwatermeters_water_meter_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watergridwatermeters_water_meter_id ON bronze.water_grid_water_meters USING btree (water_meter_id);


--
-- Name: watermeterunits_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watermeterunits_created_by ON bronze.water_meter_units USING btree (created_by);


--
-- Name: watermeterunits_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watermeterunits_unit_id ON bronze.water_meter_units USING btree (unit_id);


--
-- Name: watermeterunits_unit_id_water_meter_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watermeterunits_unit_id_water_meter_id ON bronze.water_meter_units USING btree (unit_id, water_meter_id);


--
-- Name: watermeterunits_water_meter_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watermeterunits_water_meter_id ON bronze.water_meter_units USING btree (water_meter_id);


--
-- Name: watertank_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertank_created_by ON bronze.water_tank USING btree (created_by);


--
-- Name: watertank_location_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertank_location_id ON bronze.water_tank USING btree (location_id);


--
-- Name: watertank_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watertank_name ON bronze.water_tank USING btree (name);


--
-- Name: watertank_type_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertank_type_id ON bronze.water_tank USING btree (type_id);


--
-- Name: watertank_water_source_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertank_water_source_id ON bronze.water_tank USING btree (water_source_id);


--
-- Name: watertanktype_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertanktype_created_by ON bronze.water_tank_type USING btree (created_by);


--
-- Name: watertankunits_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertankunits_created_by ON bronze.water_tank_units USING btree (created_by);


--
-- Name: watertankunits_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertankunits_unit_id ON bronze.water_tank_units USING btree (unit_id);


--
-- Name: watertankunits_water_tank_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertankunits_water_tank_id ON bronze.water_tank_units USING btree (water_tank_id);


--
-- Name: watertankunits_water_tank_id_unit_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watertankunits_water_tank_id_unit_id ON bronze.water_tank_units USING btree (water_tank_id, unit_id);


--
-- Name: watertankwatersensors_category_name; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertankwatersensors_category_name ON bronze.water_tank_water_sensors USING btree (category_name);


--
-- Name: watertankwatersensors_control_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertankwatersensors_control_id ON bronze.water_tank_water_sensors USING btree (control_id);


--
-- Name: watertankwatersensors_created_by; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertankwatersensors_created_by ON bronze.water_tank_water_sensors USING btree (created_by);


--
-- Name: watertankwatersensors_telemetry_key; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertankwatersensors_telemetry_key ON bronze.water_tank_water_sensors USING btree (telemetry_key);


--
-- Name: watertankwatersensors_telemetry_key_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertankwatersensors_telemetry_key_id ON bronze.water_tank_water_sensors USING btree (telemetry_key_id);


--
-- Name: watertankwatersensors_water_sensor_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertankwatersensors_water_sensor_id ON bronze.water_tank_water_sensors USING btree (water_sensor_id);


--
-- Name: watertankwatersensors_water_tank_id; Type: INDEX; Schema: bronze; Owner: -
--

CREATE INDEX watertankwatersensors_water_tank_id ON bronze.water_tank_water_sensors USING btree (water_tank_id);


--
-- Name: watertankwatersensors_water_tank_id_water_sensor_id_tele_03a1fb; Type: INDEX; Schema: bronze; Owner: -
--

CREATE UNIQUE INDEX watertankwatersensors_water_tank_id_water_sensor_id_tele_03a1fb ON bronze.water_tank_water_sensors USING btree (water_tank_id, water_sensor_id, telemetry_key, category_name);


--
-- Name: device add_alarm_to_device_constraint; Type: TRIGGER; Schema: bronze; Owner: -
--

CREATE TRIGGER add_alarm_to_device_constraint AFTER INSERT ON bronze.device FOR EACH ROW EXECUTE FUNCTION bronze.add_alarm_to_device();


--
-- Name: units add_unit_role; Type: TRIGGER; Schema: bronze; Owner: -
--

CREATE TRIGGER add_unit_role AFTER INSERT ON bronze.units FOR EACH ROW EXECUTE FUNCTION bronze.link_unit_with_parent_roles();


--
-- Name: schedules before_delete_schedule; Type: TRIGGER; Schema: bronze; Owner: -
--

CREATE TRIGGER before_delete_schedule BEFORE DELETE ON bronze.schedules FOR EACH ROW EXECUTE FUNCTION bronze.archive_deleted_schedule();


--
-- Name: budgets check_facility_budget_duplication_constraint; Type: TRIGGER; Schema: bronze; Owner: -
--

CREATE TRIGGER check_facility_budget_duplication_constraint BEFORE INSERT ON bronze.budgets FOR EACH ROW EXECUTE FUNCTION bronze.check_facility_budget_duplication();


--
-- Name: users check_facility_id_not_null_unit_constraint; Type: TRIGGER; Schema: bronze; Owner: -
--

CREATE TRIGGER check_facility_id_not_null_unit_constraint BEFORE INSERT ON bronze.users FOR EACH ROW EXECUTE FUNCTION bronze.check_facility_id_not_null();


--
-- Name: water_tank_water_sensors check_sensor_in_device_sensors_constraint; Type: TRIGGER; Schema: bronze; Owner: -
--

CREATE TRIGGER check_sensor_in_device_sensors_constraint BEFORE INSERT ON bronze.water_tank_water_sensors FOR EACH ROW EXECUTE FUNCTION bronze.check_sensor_in_device_sensors();


--
-- Name: device_sensors check_sensor_in_tank_sensors_constraint; Type: TRIGGER; Schema: bronze; Owner: -
--

CREATE TRIGGER check_sensor_in_tank_sensors_constraint BEFORE INSERT ON bronze.device_sensors FOR EACH ROW EXECUTE FUNCTION bronze.check_sensor_in_tank_sensors();


--
-- Name: addresses addresses_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.addresses
    ADD CONSTRAINT addresses_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: alarm_acknowledgements alarm_acknowledgements_acknowledged_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_acknowledgements
    ADD CONSTRAINT alarm_acknowledgements_acknowledged_by_fkey FOREIGN KEY (acknowledged_by) REFERENCES bronze.users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_acknowledgements alarm_acknowledgements_alarm_configuration_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_acknowledgements
    ADD CONSTRAINT alarm_acknowledgements_alarm_configuration_id_fkey FOREIGN KEY (alarm_configuration_id) REFERENCES bronze.alarm_configurations(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_acknowledgements alarm_acknowledgements_device_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_acknowledgements
    ADD CONSTRAINT alarm_acknowledgements_device_id_fkey FOREIGN KEY (device_id) REFERENCES bronze.device(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_configurations alarm_configurations_alarm_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_configurations
    ADD CONSTRAINT alarm_configurations_alarm_type_id_fkey FOREIGN KEY (alarm_type_id) REFERENCES bronze.alarm_types(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_configurations alarm_configurations_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_configurations
    ADD CONSTRAINT alarm_configurations_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_configurations_history alarm_configurations_history_alarm_configuration_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_configurations_history
    ADD CONSTRAINT alarm_configurations_history_alarm_configuration_id_fkey FOREIGN KEY (alarm_configuration_id) REFERENCES bronze.alarm_configurations(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_configurations_history alarm_configurations_history_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_configurations_history
    ADD CONSTRAINT alarm_configurations_history_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_configurations_history alarm_configurations_history_updated_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_configurations_history
    ADD CONSTRAINT alarm_configurations_history_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES bronze.users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_configurations alarm_configurations_severity_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_configurations
    ADD CONSTRAINT alarm_configurations_severity_id_fkey FOREIGN KEY (severity_id) REFERENCES bronze.alarms_severities(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_contact_groups alarm_contact_groups_alarm_configuration_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_contact_groups
    ADD CONSTRAINT alarm_contact_groups_alarm_configuration_id_fkey FOREIGN KEY (alarm_configuration_id) REFERENCES bronze.alarm_configurations(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_contact_groups alarm_contact_groups_contact_label_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_contact_groups
    ADD CONSTRAINT alarm_contact_groups_contact_label_id_fkey FOREIGN KEY (contact_label_id) REFERENCES bronze.labels(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_contact_methods alarm_contact_methods_alarm_configuration_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_contact_methods
    ADD CONSTRAINT alarm_contact_methods_alarm_configuration_id_fkey FOREIGN KEY (alarm_configuration_id) REFERENCES bronze.alarm_configurations(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_contact_methods alarm_contact_methods_contact_method_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_contact_methods
    ADD CONSTRAINT alarm_contact_methods_contact_method_id_fkey FOREIGN KEY (contact_method_id) REFERENCES bronze.contact_methods(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_contacts alarm_contacts_alarm_configuration_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_contacts
    ADD CONSTRAINT alarm_contacts_alarm_configuration_id_fkey FOREIGN KEY (alarm_configuration_id) REFERENCES bronze.alarm_configurations(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_contacts alarm_contacts_contact_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_contacts
    ADD CONSTRAINT alarm_contacts_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES bronze.contacts(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_device alarm_device_alarm_configuration_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_device
    ADD CONSTRAINT alarm_device_alarm_configuration_id_fkey FOREIGN KEY (alarm_configuration_id) REFERENCES bronze.alarm_configurations(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_device alarm_device_alarm_level_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_device
    ADD CONSTRAINT alarm_device_alarm_level_id_fkey FOREIGN KEY (alarm_level_id) REFERENCES bronze.alarm_levels(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_device alarm_device_device_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_device
    ADD CONSTRAINT alarm_device_device_id_fkey FOREIGN KEY (device_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_device_mapping alarm_device_mapping_alarm_configuration_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_device_mapping
    ADD CONSTRAINT alarm_device_mapping_alarm_configuration_id_fkey FOREIGN KEY (alarm_configuration_id) REFERENCES bronze.alarm_configurations(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_device_mapping alarm_device_mapping_alarm_level_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_device_mapping
    ADD CONSTRAINT alarm_device_mapping_alarm_level_id_fkey FOREIGN KEY (alarm_level_id) REFERENCES bronze.alarm_levels(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_device_mapping alarm_device_mapping_device_category_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_device_mapping
    ADD CONSTRAINT alarm_device_mapping_device_category_id_fkey FOREIGN KEY (device_category_id) REFERENCES bronze.devices_categories(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_device_mapping alarm_device_mapping_device_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_device_mapping
    ADD CONSTRAINT alarm_device_mapping_device_type_id_fkey FOREIGN KEY (device_type_id) REFERENCES bronze.devices_types(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_device_mapping alarm_device_mapping_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_device_mapping
    ADD CONSTRAINT alarm_device_mapping_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_logs alarm_logs_alarm_configuration_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_logs
    ADD CONSTRAINT alarm_logs_alarm_configuration_id_fkey FOREIGN KEY (alarm_configuration_id) REFERENCES bronze.alarm_configurations(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_logs alarm_logs_device_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_logs
    ADD CONSTRAINT alarm_logs_device_id_fkey FOREIGN KEY (device_id) REFERENCES bronze.device(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_logs alarm_logs_log_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_logs
    ADD CONSTRAINT alarm_logs_log_type_id_fkey FOREIGN KEY (log_type_id) REFERENCES bronze.alarm_log_types(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_notifications alarm_notifications_alarm_configuration_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_notifications
    ADD CONSTRAINT alarm_notifications_alarm_configuration_id_fkey FOREIGN KEY (alarm_configuration_id) REFERENCES bronze.alarm_configurations(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_notifications alarm_notifications_device_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_notifications
    ADD CONSTRAINT alarm_notifications_device_id_fkey FOREIGN KEY (device_id) REFERENCES bronze.device(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_notifications alarm_notifications_notification_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_notifications
    ADD CONSTRAINT alarm_notifications_notification_id_fkey FOREIGN KEY (notification_id) REFERENCES bronze.notifications(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alarm_telemetry_keys alarm_telemetry_keys_alarm_configuration_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_telemetry_keys
    ADD CONSTRAINT alarm_telemetry_keys_alarm_configuration_id_fkey FOREIGN KEY (alarm_configuration_id) REFERENCES bronze.alarm_configurations(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarm_telemetry_keys alarm_telemetry_keys_telemetry_key_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarm_telemetry_keys
    ADD CONSTRAINT alarm_telemetry_keys_telemetry_key_id_fkey FOREIGN KEY (telemetry_key_id) REFERENCES bronze.telemetries_dictionaries(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: alarms_severities alarms_severities_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.alarms_severities
    ADD CONSTRAINT alarms_severities_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: appliances appliances_category_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.appliances
    ADD CONSTRAINT appliances_category_id_fkey FOREIGN KEY (category_id) REFERENCES bronze.appliance_category(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: appliances appliances_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.appliances
    ADD CONSTRAINT appliances_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: appliances appliances_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.appliances
    ADD CONSTRAINT appliances_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: appliances appliances_meter_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.appliances
    ADD CONSTRAINT appliances_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES bronze.energy_meters(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: appliances appliances_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.appliances
    ADD CONSTRAINT appliances_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: attempted_logins attempted_logins_user_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.attempted_logins
    ADD CONSTRAINT attempted_logins_user_id_fkey FOREIGN KEY (user_id) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: banned_jtis banned_jtis_user_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.banned_jtis
    ADD CONSTRAINT banned_jtis_user_id_fkey FOREIGN KEY (user_id) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: budgets budgets_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.budgets
    ADD CONSTRAINT budgets_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: budgets budgets_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.budgets
    ADD CONSTRAINT budgets_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: budgets budgets_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.budgets
    ADD CONSTRAINT budgets_type_id_fkey FOREIGN KEY (type_id) REFERENCES bronze.budget_types(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: clients clients_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.clients
    ADD CONSTRAINT clients_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: consumption_categories consumption_categories_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.consumption_categories
    ADD CONSTRAINT consumption_categories_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: consumption_categories consumption_categories_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.consumption_categories
    ADD CONSTRAINT consumption_categories_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: consumption_categories_grid_billing_accounts_types consumption_categories_grid_b_grid_billing_account_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.consumption_categories_grid_billing_accounts_types
    ADD CONSTRAINT consumption_categories_grid_b_grid_billing_account_type_id_fkey FOREIGN KEY (grid_billing_account_type_id) REFERENCES bronze.grid_billing_accounts_types(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: consumption_categories_grid_billing_accounts_types consumption_categories_grid_billin_consumption_category_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.consumption_categories_grid_billing_accounts_types
    ADD CONSTRAINT consumption_categories_grid_billin_consumption_category_id_fkey FOREIGN KEY (consumption_category_id) REFERENCES bronze.consumption_categories(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: consumption_categories_grid_billing_accounts_types consumption_categories_grid_billing_accounts_ty_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.consumption_categories_grid_billing_accounts_types
    ADD CONSTRAINT consumption_categories_grid_billing_accounts_ty_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: contact_labels contact_labels_contact_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.contact_labels
    ADD CONSTRAINT contact_labels_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES bronze.contacts(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: contact_labels contact_labels_label_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.contact_labels
    ADD CONSTRAINT contact_labels_label_id_fkey FOREIGN KEY (label_id) REFERENCES bronze.labels(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: contact_method_mapping contact_method_mapping_contact_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.contact_method_mapping
    ADD CONSTRAINT contact_method_mapping_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES bronze.contacts(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: contact_method_mapping contact_method_mapping_contact_method_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.contact_method_mapping
    ADD CONSTRAINT contact_method_mapping_contact_method_id_fkey FOREIGN KEY (contact_method_id) REFERENCES bronze.contact_methods(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: contacts contacts_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.contacts
    ADD CONSTRAINT contacts_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: contacts contacts_user_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.contacts
    ADD CONSTRAINT contacts_user_id_fkey FOREIGN KEY (user_id) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: device device_client_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device
    ADD CONSTRAINT device_client_id_fkey FOREIGN KEY (client_id) REFERENCES bronze.clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: device_control_labels device_control_labels_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_control_labels
    ADD CONSTRAINT device_control_labels_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: device_control_labels device_control_labels_device_control_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_control_labels
    ADD CONSTRAINT device_control_labels_device_control_id_fkey FOREIGN KEY (device_control_id) REFERENCES bronze.device_controls(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: device_control_labels device_control_labels_label_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_control_labels
    ADD CONSTRAINT device_control_labels_label_id_fkey FOREIGN KEY (label_id) REFERENCES bronze.labels(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: device_controls device_controls_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_controls
    ADD CONSTRAINT device_controls_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_controls device_controls_device_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_controls
    ADD CONSTRAINT device_controls_device_id_fkey FOREIGN KEY (device_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_controls device_controls_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_controls
    ADD CONSTRAINT device_controls_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_controls_unit_pinned device_controls_unit_pinned_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_controls_unit_pinned
    ADD CONSTRAINT device_controls_unit_pinned_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_controls_unit_pinned device_controls_unit_pinned_user_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_controls_unit_pinned
    ADD CONSTRAINT device_controls_unit_pinned_user_id_fkey FOREIGN KEY (user_id) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device device_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device
    ADD CONSTRAINT device_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: device_credentials device_credentials_device_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_credentials
    ADD CONSTRAINT device_credentials_device_id_fkey FOREIGN KEY (device_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device device_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device
    ADD CONSTRAINT device_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: device_sensors device_sensors_category_name_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_sensors
    ADD CONSTRAINT device_sensors_category_name_fkey FOREIGN KEY (category_name) REFERENCES bronze.devices_categories(name) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_sensors device_sensors_control_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_sensors
    ADD CONSTRAINT device_sensors_control_id_fkey FOREIGN KEY (control_id) REFERENCES bronze.device_controls(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_sensors device_sensors_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_sensors
    ADD CONSTRAINT device_sensors_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_sensors device_sensors_device_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_sensors
    ADD CONSTRAINT device_sensors_device_id_fkey FOREIGN KEY (device_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_sensors device_sensors_sensor_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_sensors
    ADD CONSTRAINT device_sensors_sensor_id_fkey FOREIGN KEY (sensor_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_sensors device_sensors_telemetry_key_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_sensors
    ADD CONSTRAINT device_sensors_telemetry_key_fkey FOREIGN KEY (telemetry_key) REFERENCES bronze.telemetries_dictionaries(key) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_sensors device_sensors_telemetry_key_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_sensors
    ADD CONSTRAINT device_sensors_telemetry_key_id_fkey FOREIGN KEY (telemetry_key_id) REFERENCES bronze.telemetries_dictionaries(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_time device_time_device_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_time
    ADD CONSTRAINT device_time_device_id_fkey FOREIGN KEY (device_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device_time device_time_telemetry_key_name_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_time
    ADD CONSTRAINT device_time_telemetry_key_name_fkey FOREIGN KEY (telemetry_key_name) REFERENCES bronze.telemetries_dictionaries(key) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: device device_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device
    ADD CONSTRAINT device_type_id_fkey FOREIGN KEY (type_id) REFERENCES bronze.devices_types(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: device device_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device
    ADD CONSTRAINT device_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: devices_types devices_types_category_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.devices_types
    ADD CONSTRAINT devices_types_category_id_fkey FOREIGN KEY (category_id) REFERENCES bronze.devices_categories(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: devices_types devices_types_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.devices_types
    ADD CONSTRAINT devices_types_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_bills_tracking energy_bills_tracking_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_bills_tracking
    ADD CONSTRAINT energy_bills_tracking_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_bills_tracking energy_bills_tracking_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_bills_tracking
    ADD CONSTRAINT energy_bills_tracking_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_bills_tracking energy_bills_tracking_grid_billing_account_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_bills_tracking
    ADD CONSTRAINT energy_bills_tracking_grid_billing_account_id_fkey FOREIGN KEY (grid_billing_account_id) REFERENCES bronze.grid_billing_accounts(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_meter_phase_map energy_meter_phase_map_child_device_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meter_phase_map
    ADD CONSTRAINT energy_meter_phase_map_child_device_fkey FOREIGN KEY (child_device) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_meter_phase_map energy_meter_phase_map_parent_device_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meter_phase_map
    ADD CONSTRAINT energy_meter_phase_map_parent_device_fkey FOREIGN KEY (parent_device) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_meters energy_meters_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meters
    ADD CONSTRAINT energy_meters_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_meters energy_meters_device_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meters
    ADD CONSTRAINT energy_meters_device_id_fkey FOREIGN KEY (device_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_meters energy_meters_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meters
    ADD CONSTRAINT energy_meters_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_meters energy_meters_grid_billing_account_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meters
    ADD CONSTRAINT energy_meters_grid_billing_account_id_fkey FOREIGN KEY (grid_billing_account_id) REFERENCES bronze.grid_billing_accounts(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_meters energy_meters_parent_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meters
    ADD CONSTRAINT energy_meters_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES bronze.energy_meters(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_meters energy_meters_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meters
    ADD CONSTRAINT energy_meters_type_id_fkey FOREIGN KEY (type_id) REFERENCES bronze.energy_meters_types(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_meters energy_meters_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_meters
    ADD CONSTRAINT energy_meters_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: energy_saving_recommendations energy_saving_recommendations_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.energy_saving_recommendations
    ADD CONSTRAINT energy_saving_recommendations_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: facilities facilities_address_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.facilities
    ADD CONSTRAINT facilities_address_id_fkey FOREIGN KEY (address_id) REFERENCES bronze.addresses(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: facilities facilities_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.facilities
    ADD CONSTRAINT facilities_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: facilities facilities_facility_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.facilities
    ADD CONSTRAINT facilities_facility_type_id_fkey FOREIGN KEY (facility_type_id) REFERENCES bronze.facilities_types(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: facilities_types facilities_types_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.facilities_types
    ADD CONSTRAINT facilities_types_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: facilities facilities_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.facilities
    ADD CONSTRAINT facilities_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: firmwares firmwares_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.firmwares
    ADD CONSTRAINT firmwares_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: deleted_schedules fk_deleted_by; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.deleted_schedules
    ADD CONSTRAINT fk_deleted_by FOREIGN KEY (deleted_by) REFERENCES bronze.users(id);


--
-- Name: device fk_label_id; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device
    ADD CONSTRAINT fk_label_id FOREIGN KEY (label_id) REFERENCES bronze.labels(id);


--
-- Name: water_tank fk_label_id; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank
    ADD CONSTRAINT fk_label_id FOREIGN KEY (label_id) REFERENCES bronze.labels(id);


--
-- Name: device_controls fk_telemetry_key; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.device_controls
    ADD CONSTRAINT fk_telemetry_key FOREIGN KEY (telemetry_key) REFERENCES bronze.telemetries_dictionaries(key);


--
-- Name: floor_plan floor_plan_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.floor_plan
    ADD CONSTRAINT floor_plan_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: floor_plan floor_plan_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.floor_plan
    ADD CONSTRAINT floor_plan_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: forget_password forget_password_user_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.forget_password
    ADD CONSTRAINT forget_password_user_id_fkey FOREIGN KEY (user_id) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: grid_billing_accounts grid_billing_accounts_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.grid_billing_accounts
    ADD CONSTRAINT grid_billing_accounts_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: grid_billing_accounts grid_billing_accounts_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.grid_billing_accounts
    ADD CONSTRAINT grid_billing_accounts_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: grid_billing_accounts grid_billing_accounts_service_class_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.grid_billing_accounts
    ADD CONSTRAINT grid_billing_accounts_service_class_id_fkey FOREIGN KEY (service_class_id) REFERENCES bronze.grid_billing_accounts_service_classes(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: grid_billing_accounts_service_classes grid_billing_accounts_service_classes_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.grid_billing_accounts_service_classes
    ADD CONSTRAINT grid_billing_accounts_service_classes_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: grid_billing_accounts_service_classes grid_billing_accounts_service_classes_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.grid_billing_accounts_service_classes
    ADD CONSTRAINT grid_billing_accounts_service_classes_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: grid_billing_accounts grid_billing_accounts_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.grid_billing_accounts
    ADD CONSTRAINT grid_billing_accounts_type_id_fkey FOREIGN KEY (type_id) REFERENCES bronze.grid_billing_accounts_types(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: grid_billing_accounts grid_billing_accounts_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.grid_billing_accounts
    ADD CONSTRAINT grid_billing_accounts_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: label_types label_types_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.label_types
    ADD CONSTRAINT label_types_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: labels labels_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.labels
    ADD CONSTRAINT labels_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: labels labels_label_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.labels
    ADD CONSTRAINT labels_label_type_id_fkey FOREIGN KEY (label_type_id) REFERENCES bronze.label_types(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: modules modules_parent_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.modules
    ADD CONSTRAINT modules_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES bronze.modules(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: mqtt_service_accounts_allowed_topics mqtt_service_accounts_allowed_topi_mqtt_service_account_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.mqtt_service_accounts_allowed_topics
    ADD CONSTRAINT mqtt_service_accounts_allowed_topi_mqtt_service_account_id_fkey FOREIGN KEY (mqtt_service_account_id) REFERENCES bronze.mqtt_service_accounts(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: mqtt_service_accounts_allowed_topics mqtt_service_accounts_allowed_topics_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.mqtt_service_accounts_allowed_topics
    ADD CONSTRAINT mqtt_service_accounts_allowed_topics_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: mqtt_service_accounts_allowed_topics mqtt_service_accounts_allowed_topics_mqtt_topic_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.mqtt_service_accounts_allowed_topics
    ADD CONSTRAINT mqtt_service_accounts_allowed_topics_mqtt_topic_id_fkey FOREIGN KEY (mqtt_topic_id) REFERENCES bronze.mqtt_topics(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: mqtt_service_accounts mqtt_service_accounts_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.mqtt_service_accounts
    ADD CONSTRAINT mqtt_service_accounts_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: mqtt_service_accounts mqtt_service_accounts_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.mqtt_service_accounts
    ADD CONSTRAINT mqtt_service_accounts_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: mqtt_topics mqtt_topics_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.mqtt_topics
    ADD CONSTRAINT mqtt_topics_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: multi_factor_authentication_factors multi_factor_authentication_factors_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.multi_factor_authentication_factors
    ADD CONSTRAINT multi_factor_authentication_factors_type_id_fkey FOREIGN KEY (type_id) REFERENCES bronze.multi_factor_authentication_types(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: notifications notifications_contact_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.notifications
    ADD CONSTRAINT notifications_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES bronze.contacts(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: notifications notifications_contact_method_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.notifications
    ADD CONSTRAINT notifications_contact_method_id_fkey FOREIGN KEY (contact_method_id) REFERENCES bronze.contact_methods(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: notifications notifications_notification_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.notifications
    ADD CONSTRAINT notifications_notification_type_id_fkey FOREIGN KEY (notification_type_id) REFERENCES bronze.notification_types(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: overlay_controllers overlay_controllers_controller_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.overlay_controllers
    ADD CONSTRAINT overlay_controllers_controller_id_fkey FOREIGN KEY (controller_id) REFERENCES bronze.device_controls(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: overlay_controllers overlay_controllers_overlay_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.overlay_controllers
    ADD CONSTRAINT overlay_controllers_overlay_id_fkey FOREIGN KEY (overlay_id) REFERENCES bronze.overlays(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: overlays overlays_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.overlays
    ADD CONSTRAINT overlays_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: overlays overlays_floor_plan_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.overlays
    ADD CONSTRAINT overlays_floor_plan_id_fkey FOREIGN KEY (floor_plan_id) REFERENCES bronze.floor_plan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: overlays overlays_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.overlays
    ADD CONSTRAINT overlays_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: permissions permissions_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.permissions
    ADD CONSTRAINT permissions_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: role_module_permission role_module_permission_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.role_module_permission
    ADD CONSTRAINT role_module_permission_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: role_module_permission role_module_permission_module_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.role_module_permission
    ADD CONSTRAINT role_module_permission_module_id_fkey FOREIGN KEY (module_id) REFERENCES bronze.modules(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: role_module_permission role_module_permission_permission_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.role_module_permission
    ADD CONSTRAINT role_module_permission_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES bronze.permissions(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: role_module_permission role_module_permission_role_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.role_module_permission
    ADD CONSTRAINT role_module_permission_role_id_fkey FOREIGN KEY (role_id) REFERENCES bronze.roles(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: role_units role_units_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.role_units
    ADD CONSTRAINT role_units_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: role_units role_units_role_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.role_units
    ADD CONSTRAINT role_units_role_id_fkey FOREIGN KEY (role_id) REFERENCES bronze.roles(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: role_units role_units_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.role_units
    ADD CONSTRAINT role_units_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: roles roles_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.roles
    ADD CONSTRAINT roles_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: roles roles_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.roles
    ADD CONSTRAINT roles_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: schedule_controllers schedule_controllers_controller_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_controllers
    ADD CONSTRAINT schedule_controllers_controller_id_fkey FOREIGN KEY (controller_id) REFERENCES bronze.device_controls(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: schedule_controllers schedule_controllers_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_controllers
    ADD CONSTRAINT schedule_controllers_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: schedule_controllers schedule_controllers_schedule_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_controllers
    ADD CONSTRAINT schedule_controllers_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES bronze.schedules(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: schedule_jobs schedule_jobs_schedule_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_jobs
    ADD CONSTRAINT schedule_jobs_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES bronze.schedules(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: schedule_labels schedule_labels_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_labels
    ADD CONSTRAINT schedule_labels_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: schedule_labels schedule_labels_label_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_labels
    ADD CONSTRAINT schedule_labels_label_id_fkey FOREIGN KEY (label_id) REFERENCES bronze.labels(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: schedule_labels schedule_labels_schedule_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_labels
    ADD CONSTRAINT schedule_labels_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES bronze.schedules(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: schedule_units schedule_units_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_units
    ADD CONSTRAINT schedule_units_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: schedule_units schedule_units_schedule_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_units
    ADD CONSTRAINT schedule_units_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES bronze.schedules(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: schedule_units schedule_units_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedule_units
    ADD CONSTRAINT schedule_units_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: schedules schedules_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.schedules
    ADD CONSTRAINT schedules_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: tariff_categories tariff_categories_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.tariff_categories
    ADD CONSTRAINT tariff_categories_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: tariff_categories tariff_categories_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.tariff_categories
    ADD CONSTRAINT tariff_categories_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: telemetries_notif telemetries_notif_device_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.telemetries_notif
    ADD CONSTRAINT telemetries_notif_device_id_fkey FOREIGN KEY (device_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: telemetries_notif_users telemetries_notif_users_notif_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.telemetries_notif_users
    ADD CONSTRAINT telemetries_notif_users_notif_id_fkey FOREIGN KEY (notif_id) REFERENCES bronze.telemetries_notif(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: telemetries_notif_users telemetries_notif_users_user_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.telemetries_notif_users
    ADD CONSTRAINT telemetries_notif_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: units units_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.units
    ADD CONSTRAINT units_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: units units_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.units
    ADD CONSTRAINT units_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: units units_icon_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.units
    ADD CONSTRAINT units_icon_id_fkey FOREIGN KEY (icon_id) REFERENCES bronze.icons(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: units units_parent_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.units
    ADD CONSTRAINT units_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES bronze.units(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: units units_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.units
    ADD CONSTRAINT units_type_id_fkey FOREIGN KEY (type_id) REFERENCES bronze.units_types(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: units_types units_types_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.units_types
    ADD CONSTRAINT units_types_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: units_types units_types_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.units_types
    ADD CONSTRAINT units_types_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: units_types units_types_icon_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.units_types
    ADD CONSTRAINT units_types_icon_id_fkey FOREIGN KEY (icon_id) REFERENCES bronze.icons(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: upload_batch_items upload_batch_items_batch_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.upload_batch_items
    ADD CONSTRAINT upload_batch_items_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES bronze.upload_batches(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: upload_batch_items upload_batch_items_status_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.upload_batch_items
    ADD CONSTRAINT upload_batch_items_status_id_fkey FOREIGN KEY (status_id) REFERENCES bronze.upload_status(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: upload_batches upload_batches_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.upload_batches
    ADD CONSTRAINT upload_batches_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: upload_batches upload_batches_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.upload_batches
    ADD CONSTRAINT upload_batches_type_id_fkey FOREIGN KEY (type_id) REFERENCES bronze.upload_batches_types(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: users users_address_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.users
    ADD CONSTRAINT users_address_id_fkey FOREIGN KEY (address_id) REFERENCES bronze.addresses(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: users users_facility_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.users
    ADD CONSTRAINT users_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES bronze.facilities(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: users users_mfa_factor_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.users
    ADD CONSTRAINT users_mfa_factor_id_fkey FOREIGN KEY (mfa_factor_id) REFERENCES bronze.multi_factor_authentication_factors(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: users users_mqtt_account_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.users
    ADD CONSTRAINT users_mqtt_account_id_fkey FOREIGN KEY (mqtt_account_id) REFERENCES bronze.mqtt_service_accounts(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: users users_role_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.users
    ADD CONSTRAINT users_role_id_fkey FOREIGN KEY (role_id) REFERENCES bronze.roles(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: water_bill water_bill_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_bill
    ADD CONSTRAINT water_bill_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_bill water_bill_water_grid_account_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_bill
    ADD CONSTRAINT water_bill_water_grid_account_id_fkey FOREIGN KEY (water_grid_account_id) REFERENCES bronze.water_grid_account(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_bill_water_meter_consume water_bill_water_meter_consume_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_bill_water_meter_consume
    ADD CONSTRAINT water_bill_water_meter_consume_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_bill_water_meter_consume water_bill_water_meter_consume_water_bill_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_bill_water_meter_consume
    ADD CONSTRAINT water_bill_water_meter_consume_water_bill_id_fkey FOREIGN KEY (water_bill_id) REFERENCES bronze.water_bill(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_bill_water_meter_consume water_bill_water_meter_consume_water_meter_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_bill_water_meter_consume
    ADD CONSTRAINT water_bill_water_meter_consume_water_meter_id_fkey FOREIGN KEY (water_meter_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account water_grid_account_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account
    ADD CONSTRAINT water_grid_account_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_global_types water_grid_account_global_types_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_global_types
    ADD CONSTRAINT water_grid_account_global_types_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_global_types water_grid_account_global_types_global_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_global_types
    ADD CONSTRAINT water_grid_account_global_types_global_type_id_fkey FOREIGN KEY (global_type_id) REFERENCES bronze.water_grid_account_service_global(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_global_types water_grid_account_global_types_water_grid_account_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_global_types
    ADD CONSTRAINT water_grid_account_global_types_water_grid_account_id_fkey FOREIGN KEY (water_grid_account_id) REFERENCES bronze.water_grid_account(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_service_class water_grid_account_service_class_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_service_class
    ADD CONSTRAINT water_grid_account_service_class_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account water_grid_account_service_class_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account
    ADD CONSTRAINT water_grid_account_service_class_id_fkey FOREIGN KEY (service_class_id) REFERENCES bronze.water_grid_account_service_class(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_service_class water_grid_account_service_class_water_grid_provider_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_service_class
    ADD CONSTRAINT water_grid_account_service_class_water_grid_provider_id_fkey FOREIGN KEY (water_grid_provider_id) REFERENCES bronze.water_grid_provider(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_service_global water_grid_account_service_global_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_service_global
    ADD CONSTRAINT water_grid_account_service_global_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_service_global water_grid_account_service_global_water_grid_provider_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_service_global
    ADD CONSTRAINT water_grid_account_service_global_water_grid_provider_id_fkey FOREIGN KEY (water_grid_provider_id) REFERENCES bronze.water_grid_provider(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_service_sub_type water_grid_account_service_sub_type_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_service_sub_type
    ADD CONSTRAINT water_grid_account_service_sub_type_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_service_type water_grid_account_service_type_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_service_type
    ADD CONSTRAINT water_grid_account_service_type_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account water_grid_account_service_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account
    ADD CONSTRAINT water_grid_account_service_type_id_fkey FOREIGN KEY (service_type_id) REFERENCES bronze.water_grid_account_service_type(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_service_type water_grid_account_service_type_water_grid_provider_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_service_type
    ADD CONSTRAINT water_grid_account_service_type_water_grid_provider_id_fkey FOREIGN KEY (water_grid_provider_id) REFERENCES bronze.water_grid_provider(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_units water_grid_account_units_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_units
    ADD CONSTRAINT water_grid_account_units_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_units water_grid_account_units_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_units
    ADD CONSTRAINT water_grid_account_units_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account_units water_grid_account_units_water_grid_account_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account_units
    ADD CONSTRAINT water_grid_account_units_water_grid_account_id_fkey FOREIGN KEY (water_grid_account_id) REFERENCES bronze.water_grid_account(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_account water_grid_account_water_grid_provider_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_account
    ADD CONSTRAINT water_grid_account_water_grid_provider_id_fkey FOREIGN KEY (water_grid_provider_id) REFERENCES bronze.water_grid_provider(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_provider water_grid_provider_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_provider
    ADD CONSTRAINT water_grid_provider_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_water_meters water_grid_water_meters_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_water_meters
    ADD CONSTRAINT water_grid_water_meters_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_water_meters water_grid_water_meters_water_grid_account_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_water_meters
    ADD CONSTRAINT water_grid_water_meters_water_grid_account_id_fkey FOREIGN KEY (water_grid_account_id) REFERENCES bronze.water_grid_account(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_grid_water_meters water_grid_water_meters_water_meter_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_grid_water_meters
    ADD CONSTRAINT water_grid_water_meters_water_meter_id_fkey FOREIGN KEY (water_meter_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_meter_units water_meter_units_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_meter_units
    ADD CONSTRAINT water_meter_units_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_meter_units water_meter_units_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_meter_units
    ADD CONSTRAINT water_meter_units_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_meter_units water_meter_units_water_meter_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_meter_units
    ADD CONSTRAINT water_meter_units_water_meter_id_fkey FOREIGN KEY (water_meter_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank water_tank_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank
    ADD CONSTRAINT water_tank_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank water_tank_location_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank
    ADD CONSTRAINT water_tank_location_id_fkey FOREIGN KEY (location_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank_type water_tank_type_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_type
    ADD CONSTRAINT water_tank_type_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank water_tank_type_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank
    ADD CONSTRAINT water_tank_type_id_fkey FOREIGN KEY (type_id) REFERENCES bronze.water_tank_type(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank_units water_tank_units_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_units
    ADD CONSTRAINT water_tank_units_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank_units water_tank_units_unit_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_units
    ADD CONSTRAINT water_tank_units_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES bronze.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank_units water_tank_units_water_tank_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_units
    ADD CONSTRAINT water_tank_units_water_tank_id_fkey FOREIGN KEY (water_tank_id) REFERENCES bronze.water_tank(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank_water_sensors water_tank_water_sensors_category_name_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_water_sensors
    ADD CONSTRAINT water_tank_water_sensors_category_name_fkey FOREIGN KEY (category_name) REFERENCES bronze.devices_categories(name) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank_water_sensors water_tank_water_sensors_control_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_water_sensors
    ADD CONSTRAINT water_tank_water_sensors_control_id_fkey FOREIGN KEY (control_id) REFERENCES bronze.device_controls(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank_water_sensors water_tank_water_sensors_created_by_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_water_sensors
    ADD CONSTRAINT water_tank_water_sensors_created_by_fkey FOREIGN KEY (created_by) REFERENCES bronze.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank_water_sensors water_tank_water_sensors_telemetry_key_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_water_sensors
    ADD CONSTRAINT water_tank_water_sensors_telemetry_key_fkey FOREIGN KEY (telemetry_key) REFERENCES bronze.telemetries_dictionaries(key) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank_water_sensors water_tank_water_sensors_telemetry_key_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_water_sensors
    ADD CONSTRAINT water_tank_water_sensors_telemetry_key_id_fkey FOREIGN KEY (telemetry_key_id) REFERENCES bronze.telemetries_dictionaries(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank_water_sensors water_tank_water_sensors_water_sensor_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_water_sensors
    ADD CONSTRAINT water_tank_water_sensors_water_sensor_id_fkey FOREIGN KEY (water_sensor_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank_water_sensors water_tank_water_sensors_water_tank_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank_water_sensors
    ADD CONSTRAINT water_tank_water_sensors_water_tank_id_fkey FOREIGN KEY (water_tank_id) REFERENCES bronze.water_tank(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: water_tank water_tank_water_source_id_fkey; Type: FK CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.water_tank
    ADD CONSTRAINT water_tank_water_source_id_fkey FOREIGN KEY (water_source_id) REFERENCES bronze.device(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict uDVmZxGrV9TpdFinWtZIlsAjfvCq54gNFc7JuzujOksoYUVQilpMT3YdJ0ENXwd

