--
-- PostgreSQL database dump
--

\restrict lEFF4lCbBHPCenNhQMJtxiQ9f1GHQWH0TEz0MISb0QTe5skQ4zMbB2eN6Meoafd

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
-- Name: gold; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA gold;


--
-- Name: silver; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA silver;


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


--
-- Name: classify_accumulated_energy_v2(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_accumulated_energy_v2(value double precision, prev_value double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF prev_value IS NULL THEN RETURN 'Acceptable'; END IF;  -- first-ever reading for this meter, nothing to compare
    IF value < prev_value THEN RETURN 'Invalid'; END IF;      -- decrement -- counter went backward
    RETURN 'Acceptable';
END;
$$;


--
-- Name: classify_active_power(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_active_power(p_value double precision, p_prev_value double precision, p_cb_max_kw double precision DEFAULT NULL::double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        0.0,
        p_cb_max_kw,
        0.0,
        p_cb_max_kw,
        NULL,
        NULL,
        50.0
    );
$$;


--
-- Name: classify_apparent_power(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_apparent_power(p_value double precision, p_prev_value double precision, p_user_max double precision DEFAULT NULL::double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        NULL,
        p_user_max,
        0.0,
        p_user_max,
        0.0,
        NULL,
        50.0
    );
$$;


--
-- Name: classify_consistency(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_consistency(p_total double precision, p_phase_sum double precision, p_tolerance_pct double precision DEFAULT 5.0) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_total IS NULL
          OR p_phase_sum IS NULL
            THEN NULL

        WHEN p_phase_sum = 0
            THEN CASE
                WHEN p_total = 0 THEN 'Acceptable'
                ELSE 'Invalid'
            END

        WHEN ABS(p_total - p_phase_sum)
             / ABS(p_phase_sum) * 100 > p_tolerance_pct
            THEN 'Invalid'

        ELSE 'Acceptable'
    END;
$$;


--
-- Name: classify_current(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_current(p_value double precision, p_prev_value double precision, p_cb_max_a double precision DEFAULT NULL::double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        0.0,
        p_cb_max_a,
        0.0,
        p_cb_max_a,
        NULL,
        NULL,
        50.0
    );
$$;


--
-- Name: classify_current_v2(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_current_v2(value double precision, cb_max double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    margin double precision;
    third  double precision;
BEGIN
    IF value IS NULL OR cb_max IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 0 OR value > cb_max THEN RETURN 'Critical'; END IF;

    margin := 0.15 * cb_max;
    third  := margin / 3.0;

    IF value >= margin AND value <= (cb_max - margin) THEN RETURN 'Acceptable'; END IF;

    IF (value >= third AND value < margin)
       OR (value > (cb_max - margin) AND value <= (cb_max - third)) THEN
        RETURN 'Review Required';
    END IF;

    RETURN 'Problematic';  -- remaining zones: 0-third and (cb_max-third)-cb_max
END;
$$;


--
-- Name: classify_current_v2(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_current_v2(value double precision, cb_max double precision, phase_kw double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    margin double precision;
    third  double precision;
BEGIN
    IF value IS NULL OR cb_max IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 0 THEN RETURN 'Invalid'; END IF;
    IF value > cb_max THEN RETURN 'Critical'; END IF;

    margin := 0.15 * cb_max;
    third  := margin / 3.0;

    -- Upper side -- unchanged
    IF value > (cb_max - third) THEN RETURN 'Problematic'; END IF;
    IF value > (cb_max - margin) THEN RETURN 'Review Required'; END IF;

    -- Lower fringe zone (0 to margin) -- new agreement-based logic
    IF value < margin THEN
        IF value = 0 AND phase_kw = 0 THEN RETURN 'Acceptable'; END IF;
        IF value > 0 AND phase_kw = 0 THEN RETURN 'Major Problem'; END IF;
        IF value = 0 AND phase_kw <> 0 THEN RETURN 'Major Issue'; END IF;
        RETURN 'Acceptable';  -- both nonzero -- consistent, any magnitude
    END IF;

    -- Safe middle -- unchanged
    RETURN 'Acceptable';
END;
$$;


--
-- Name: classify_energy(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_energy(p_value double precision, p_prev_value double precision, p_user_max double precision DEFAULT NULL::double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_value IS NULL THEN NULL

        WHEN p_value < 0
            THEN 'Invalid'

        WHEN p_user_max IS NOT NULL
         AND p_value > p_user_max
            THEN 'Critical'

        WHEN p_prev_value IS NOT NULL
         AND p_value < p_prev_value
            THEN 'Anomaly'

        ELSE 'Acceptable'
    END;
$$;


--
-- Name: classify_frequency(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_frequency(p_value double precision, p_prev_value double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        59.0,   -- hard_min (was 59.3)
        61.0,   -- hard_max (was 60.5)
        59.3,   -- acceptable_min (was 59.0)
        60.5,   -- acceptable_max (was 61.0)
        0.0,    -- invalid_min (unchanged)
        61.0,   -- invalid_max (unchanged)
        50.0    -- spike_pct (unchanged)
    );
$$;


--
-- Name: classify_frequency_v2(double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_frequency_v2(value double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 59 OR value > 61 THEN RETURN 'Critical'; END IF;
    IF value >= 59.3 AND value <= 60.5 THEN RETURN 'Acceptable'; END IF;
    RETURN 'Problematic';  -- remaining zones: 59-59.3 and 60.5-61
END;
$$;


--
-- Name: classify_phase_imbalance(double precision, text, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_phase_imbalance(p_imbalance_pct double precision, p_evaluation_status text, p_problematic_threshold_pct double precision DEFAULT 5.0, p_critical_threshold_pct double precision DEFAULT 5.0) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_imbalance_pct IS NULL
          OR p_evaluation_status IS NULL
            THEN NULL

        WHEN UPPER(p_evaluation_status) = 'OUTSIDE_ACCEPTABLE'
         AND p_imbalance_pct > p_critical_threshold_pct
            THEN 'Critical'

        WHEN UPPER(p_evaluation_status) = 'WITHIN_ACCEPTABLE'
         AND p_imbalance_pct > p_problematic_threshold_pct
            THEN 'Problematic'

        -- Compatibility with previous calls using EVALUATED
        WHEN UPPER(p_evaluation_status) = 'EVALUATED'
         AND p_imbalance_pct > p_critical_threshold_pct
            THEN 'Critical'

        WHEN UPPER(p_evaluation_status) = 'EVALUATED'
         AND p_imbalance_pct > p_problematic_threshold_pct
            THEN 'Problematic'

        ELSE 'Acceptable'
    END;
$$;


--
-- Name: classify_power_factor(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_power_factor(p_value double precision, p_prev_value double precision, p_spike_pct double precision DEFAULT 50.0) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_value IS NULL THEN NULL

        WHEN p_value < -1
          OR p_value > 1
            THEN 'Invalid'

        -- Problematic outranks Anomaly
        WHEN p_value < 0.6
            THEN 'Problematic'

        WHEN p_prev_value IS NOT NULL
         AND p_prev_value <> 0
         AND ABS(p_value - p_prev_value)
             / ABS(p_prev_value) * 100 >= p_spike_pct
            THEN 'Anomaly'

        WHEN p_value < 0.8
            THEN 'Review Required'

        ELSE 'Acceptable'
    END;
$$;


--
-- Name: classify_power_factor_v2(double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_power_factor_v2(value double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 0.6 OR value > 1 THEN RETURN 'Critical'; END IF;
    IF value >= 0.8 AND value <= 1 THEN RETURN 'Acceptable'; END IF;
    IF value >= 0.78 AND value < 0.8 THEN RETURN 'Review Required'; END IF;
    RETURN 'Problematic';  -- remaining zone: 0.6-0.78
END;
$$;


--
-- Name: classify_reactive_power(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_reactive_power(p_value double precision, p_prev_value double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        50.0
    );
$$;


--
-- Name: classify_standard(double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_standard(p_value double precision, p_prev_value double precision, p_hard_min double precision, p_hard_max double precision, p_acceptable_min double precision, p_acceptable_max double precision, p_invalid_min double precision DEFAULT NULL::double precision, p_invalid_max double precision DEFAULT NULL::double precision, p_spike_pct double precision DEFAULT 50.0) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_value IS NULL THEN NULL

        -- Invalid physical or sanity range
        WHEN p_invalid_min IS NOT NULL
         AND p_value < p_invalid_min
            THEN 'Invalid'

        WHEN p_invalid_max IS NOT NULL
         AND p_value > p_invalid_max
            THEN 'Invalid'

        -- Hard operational limits
        WHEN p_hard_min IS NOT NULL
         AND p_value < p_hard_min
            THEN 'Critical'

        WHEN p_hard_max IS NOT NULL
         AND p_value > p_hard_max
            THEN 'Critical'

        -- High spike against previous reading
        WHEN p_prev_value IS NOT NULL
         AND p_prev_value <> 0
         AND ABS(p_value - p_prev_value)
             / ABS(p_prev_value) * 100 >= p_spike_pct
            THEN 'Anomaly'

        -- Outside acceptable range but not outside hard limit
        WHEN p_acceptable_min IS NOT NULL
         AND p_value < p_acceptable_min
            THEN 'Review Required'

        WHEN p_acceptable_max IS NOT NULL
         AND p_value > p_acceptable_max
            THEN 'Review Required'

        ELSE 'Acceptable'
    END;
$$;


--
-- Name: classify_voltage_line(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_voltage_line(p_value double precision, p_prev_value double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        360.0,
        440.0,
        380.0,
        420.0,
        0.0,
        600.0,
        50.0
    );
$$;


--
-- Name: classify_voltage_line_v2(double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_voltage_line_v2(value double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 360 OR value > 440 THEN RETURN 'Critical'; END IF;
    IF value >= 380 AND value <= 420 THEN RETURN 'Acceptable'; END IF;
    IF (value >= 371.2 AND value < 380) OR (value > 420 AND value <= 428.8) THEN RETURN 'Review Required'; END IF;
    RETURN 'Problematic';  -- remaining zones: 360-371.2 and 428.8-440
END;
$$;


--
-- Name: classify_voltage_neutral(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_voltage_neutral(p_value double precision, p_prev_value double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        207.0,
        253.0,
        215.0,
        245.0,
        0.0,
        600.0,
        50.0
    );
$$;


--
-- Name: classify_voltage_neutral_v2(double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_voltage_neutral_v2(value double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 207 OR value > 253 THEN RETURN 'Critical'; END IF;
    IF value >= 215 AND value <= 245 THEN RETURN 'Acceptable'; END IF;
    IF (value >= 209.94 AND value < 215) OR (value > 245 AND value <= 250.06) THEN RETURN 'Review Required'; END IF;
    RETURN 'Problematic';  -- remaining zones: 207-209.94 and 250.06-253
END;
$$;


--
-- Name: status_rank(text); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.status_rank(p_status text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE p_status
        WHEN 'Acceptable'      THEN 1
        WHEN 'Review Required' THEN 2
        WHEN 'Anomaly'         THEN 3
        WHEN 'Problematic'     THEN 4
        WHEN 'Critical'        THEN 5
        WHEN 'Invalid'         THEN 6
        ELSE 0
    END;
$$;


--
-- Name: worst_status(text[]); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.worst_status(VARIADIC p_statuses text[]) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT status_value
    FROM unnest(p_statuses) AS status_value
    WHERE status_value IS NOT NULL
    ORDER BY silver.status_rank(status_value) DESC
    LIMIT 1;
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
-- Name: grid_billing_accounts_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.grid_billing_accounts_landing AS
 SELECT id,
    ((label)::text COLLATE "C") AS label,
    number,
    ((meter_serial_number)::text COLLATE "C") AS meter_serial_number,
    type_id,
    service_class_id,
    breaker_capacity,
    start_period,
    end_period,
    days,
    facility_id,
    unit_id,
    created_by,
    created_on,
    multiplication_factor
   FROM bronze.grid_billing_accounts;


--
-- Name: VIEW grid_billing_accounts_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.grid_billing_accounts_landing IS 'Landing view for bronze.grid_billing_accounts. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: grid_billing_accounts_service_classes_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.grid_billing_accounts_service_classes_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    minimal_breaker_capacity,
    maximum_breaker_capacity,
    fee,
    facility_id,
    active,
    created_by,
    created_on
   FROM bronze.grid_billing_accounts_service_classes;


--
-- Name: VIEW grid_billing_accounts_service_classes_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.grid_billing_accounts_service_classes_landing IS 'Landing view for bronze.grid_billing_accounts_service_classes. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: grid_billing_accounts_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.grid_billing_accounts_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    created_on
   FROM bronze.grid_billing_accounts_types;


--
-- Name: VIEW grid_billing_accounts_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.grid_billing_accounts_types_landing IS 'Landing view for bronze.grid_billing_accounts_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: dim_grid_billing_account_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.dim_grid_billing_account_staging AS
 SELECT gba.id AS grid_billing_account_key,
    gba.facility_id AS facility_key,
    gba.unit_id AS zone_key,
    gba.label AS account_label,
    ((gba.number)::text COLLATE "C") AS account_number,
    gba.meter_serial_number,
    gba.type_id AS account_type_key,
    gbat.name AS account_type_name,
    gba.service_class_id AS service_class_key,
    gbasc.name AS service_class_name,
    gba.breaker_capacity,
    gbasc.minimal_breaker_capacity,
    gbasc.maximum_breaker_capacity,
    gbasc.fee AS service_class_fee,
    gba.multiplication_factor,
    gba.start_period,
    gba.end_period,
    gba.days AS configured_billing_days,
    gba.created_on AS source_created_at
   FROM ((silver.grid_billing_accounts_landing gba
     LEFT JOIN silver.grid_billing_accounts_types_landing gbat ON ((gbat.id = gba.type_id)))
     LEFT JOIN silver.grid_billing_accounts_service_classes_landing gbasc ON ((gbasc.id = gba.service_class_id)));


--
-- Name: VIEW dim_grid_billing_account_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.dim_grid_billing_account_staging IS 'Grid billing-account dimension enriched with account type and service class.';


--
-- Name: billing_account; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.billing_account AS
 SELECT grid_billing_account_key,
    facility_key,
    zone_key,
    account_label,
    account_number,
    meter_serial_number,
    account_type_key,
    account_type_name,
    service_class_key,
    service_class_name,
    breaker_capacity,
    minimal_breaker_capacity,
    maximum_breaker_capacity,
    service_class_fee,
    multiplication_factor,
    start_period,
    end_period,
    configured_billing_days,
    source_created_at
   FROM silver.dim_grid_billing_account_staging;


--
-- Name: dim_date_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.dim_date_staging AS
 WITH calendar AS (
         SELECT (gs.gs)::date AS calendar_date
           FROM generate_series(('2024-01-01'::date)::timestamp with time zone, ('2030-12-31'::date)::timestamp with time zone, '1 day'::interval) gs(gs)
        )
 SELECT (to_char((calendar_date)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS date_key,
    calendar_date,
    (EXTRACT(year FROM calendar_date))::integer AS calendar_year,
    (EXTRACT(quarter FROM calendar_date))::integer AS calendar_quarter,
    (EXTRACT(month FROM calendar_date))::integer AS month_number,
    (to_char((calendar_date)::timestamp with time zone, 'Month'::text) COLLATE "C") AS month_name,
    (to_char((calendar_date)::timestamp with time zone, 'Mon'::text) COLLATE "C") AS month_short_name,
    (EXTRACT(week FROM calendar_date))::integer AS week_of_year,
    (EXTRACT(isodow FROM calendar_date))::integer AS iso_day_of_week,
    (to_char((calendar_date)::timestamp with time zone, 'Day'::text) COLLATE "C") AS day_name,
    (to_char((calendar_date)::timestamp with time zone, 'Dy'::text) COLLATE "C") AS day_short_name,
    (EXTRACT(day FROM calendar_date))::integer AS day_of_month,
    (EXTRACT(doy FROM calendar_date))::integer AS day_of_year,
    (EXTRACT(isodow FROM calendar_date) = ANY (ARRAY[(6)::numeric, (7)::numeric])) AS is_weekend,
    (date_trunc('month'::text, (calendar_date)::timestamp with time zone))::date AS month_start_date,
    ((date_trunc('month'::text, (calendar_date)::timestamp with time zone) + '1 mon -1 days'::interval))::date AS month_end_date,
    (date_trunc('quarter'::text, (calendar_date)::timestamp with time zone))::date AS quarter_start_date,
    (date_trunc('year'::text, (calendar_date)::timestamp with time zone))::date AS year_start_date
   FROM calendar;


--
-- Name: VIEW dim_date_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.dim_date_staging IS 'Role-playing date dimension for telemetry dates and billing-period dates.';


--
-- Name: date; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.date AS
 SELECT date_key,
    calendar_date,
    calendar_year,
    calendar_quarter,
    month_number,
    month_name,
    month_short_name,
    week_of_year,
    iso_day_of_week,
    day_name,
    day_short_name,
    day_of_month,
    day_of_year,
    is_weekend,
    month_start_date,
    month_end_date,
    quarter_start_date,
    year_start_date
   FROM silver.dim_date_staging;


--
-- Name: energy_bills_tracking_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_bills_tracking_landing AS
 SELECT id,
    facility_id,
    grid_billing_account_id,
    start_period,
    end_period,
    beginning_reading,
    ending_reading,
    consumption_reading,
    cost,
    ((comparing_with_last_bill)::text COLLATE "C") AS comparing_with_last_bill,
    system_beginning_reading,
    system_endng_reading,
    system_consumption_reading,
    system_estimated_cost,
    system_reading_time,
    ((comparing_with_grid_bill)::text COLLATE "C") AS comparing_with_grid_bill,
    created_by,
    created_on,
    invoice_number
   FROM bronze.energy_bills_tracking;


--
-- Name: VIEW energy_bills_tracking_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.energy_bills_tracking_landing IS 'Landing view for bronze.energy_bills_tracking. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: fact_energy_bill_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.fact_energy_bill_staging AS
 SELECT bill.id AS energy_bill_key,
    bill.facility_id AS facility_key,
    account.zone_key,
    bill.grid_billing_account_id AS grid_billing_account_key,
    (to_char((bill.start_period AT TIME ZONE 'UTC'::text), 'YYYYMMDD'::text))::integer AS start_date_key,
    (to_char((bill.end_period AT TIME ZONE 'UTC'::text), 'YYYYMMDD'::text))::integer AS end_date_key,
    bill.start_period,
    bill.end_period,
    ((bill.end_period)::date - (bill.start_period)::date) AS calculated_billing_days,
    ((bill.invoice_number)::text COLLATE "C") AS invoice_number,
    bill.beginning_reading,
    bill.ending_reading,
    bill.consumption_reading AS billed_consumption_kwh,
    bill.cost AS billed_cost,
    bill.system_beginning_reading,
    bill.system_endng_reading AS system_ending_reading,
    bill.system_consumption_reading AS system_consumption_kwh,
    bill.system_estimated_cost,
    (bill.system_consumption_reading - bill.consumption_reading) AS consumption_variance_kwh,
    (bill.system_estimated_cost - bill.cost) AS cost_variance,
    (((bill.system_consumption_reading - bill.consumption_reading) / NULLIF(bill.consumption_reading, (0)::numeric)) * (100)::numeric) AS consumption_variance_percent,
    bill.comparing_with_last_bill,
    bill.comparing_with_grid_bill,
        CASE
            WHEN (bill.system_reading_time IS NULL) THEN NULL::timestamp without time zone
            ELSE (to_timestamp((((bill.system_reading_time)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text)
        END AS system_reading_timestamp_utc,
    bill.created_on AS source_created_at
   FROM (silver.energy_bills_tracking_landing bill
     LEFT JOIN silver.dim_grid_billing_account_staging account ON ((account.grid_billing_account_key = bill.grid_billing_account_id)));


--
-- Name: VIEW fact_energy_bill_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.fact_energy_bill_staging IS 'Energy billing fact containing billed versus system-estimated consumption and cost measures.';


--
-- Name: energy_bill; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.energy_bill AS
 SELECT energy_bill_key,
    facility_key,
    zone_key,
    grid_billing_account_key,
    start_date_key,
    end_date_key,
    start_period,
    end_period,
    calculated_billing_days,
    invoice_number,
    beginning_reading,
    ending_reading,
    billed_consumption_kwh,
    billed_cost,
    system_beginning_reading,
    system_ending_reading,
    system_consumption_kwh,
    system_estimated_cost,
    consumption_variance_kwh,
    cost_variance,
    consumption_variance_percent,
    comparing_with_last_bill,
    comparing_with_grid_bill,
    system_reading_timestamp_utc,
    source_created_at
   FROM silver.fact_energy_bill_staging;


--
-- Name: fact_energy_consumption_validated; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.fact_energy_consumption_validated (
    energy_meter_key uuid,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    meter_label text COLLATE pg_catalog."C",
    reading_timestamp_utc timestamp without time zone,
    reading_timestamp_saudi timestamp without time zone,
    reading_date_saudi date,
    active_energy_cumulative_kwh double precision,
    status_kwh text,
    raw_previous_kwh double precision,
    raw_next_kwh double precision,
    consumption_cleaning_status text,
    previous_valid_timestamp timestamp without time zone,
    previous_valid_kwh double precision,
    validated_kwh_consumption double precision,
    gap_minutes numeric,
    interval_quality text
);


--
-- Name: energy_consumption_validated; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.energy_consumption_validated AS
 SELECT energy_meter_key,
    facility_key,
    zone_key,
    grid_billing_account_key,
    meter_label,
    reading_timestamp_utc,
    reading_timestamp_saudi,
    reading_date_saudi,
    active_energy_cumulative_kwh,
    previous_valid_timestamp,
    previous_valid_kwh,
    validated_kwh_consumption,
    consumption_cleaning_status,
    interval_quality,
    gap_minutes
   FROM silver.fact_energy_consumption_validated;


--
-- Name: fact_energy_readings_snapshot; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.fact_energy_readings_snapshot (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    reading_timestamp_utc timestamp without time zone NOT NULL,
    active_energy_cumulative_kwh double precision,
    reactive_energy_cumulative_kvarh double precision,
    apparent_energy_cumulative_kvah double precision,
    voltage_neutral_1_v double precision,
    voltage_neutral_2_v double precision,
    voltage_neutral_3_v double precision,
    voltage_neutral_average_v double precision,
    voltage_line_1_v double precision,
    voltage_line_2_v double precision,
    voltage_line_3_v double precision,
    voltage_line_average_v double precision,
    current_phase_1_a double precision,
    current_phase_2_a double precision,
    current_phase_3_a double precision,
    frequency_hz double precision,
    power_factor_phase_1 double precision,
    power_factor_phase_2 double precision,
    power_factor_phase_3 double precision,
    power_factor_average double precision,
    active_power_phase_1_kw double precision,
    active_power_phase_2_kw double precision,
    active_power_phase_3_kw double precision,
    active_power_total_kw double precision,
    apparent_power_phase_1_kva double precision,
    apparent_power_phase_2_kva double precision,
    apparent_power_phase_3_kva double precision,
    apparent_power_total_kva double precision,
    reactive_power_phase_1_kvar double precision,
    reactive_power_phase_2_kvar double precision,
    reactive_power_phase_3_kvar double precision,
    reactive_power_total_kvar double precision,
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_pfa text,
    status_kwh text,
    overall_status text
);


--
-- Name: energy_raw; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.energy_raw AS
 SELECT energy_meter_key,
    facility_key,
    zone_key,
    grid_billing_account_key,
    reading_timestamp_utc,
    active_energy_cumulative_kwh,
    reactive_energy_cumulative_kvarh,
    apparent_energy_cumulative_kvah,
    voltage_neutral_1_v,
    voltage_neutral_2_v,
    voltage_neutral_3_v,
    voltage_neutral_average_v,
    voltage_line_1_v,
    voltage_line_2_v,
    voltage_line_3_v,
    voltage_line_average_v,
    current_phase_1_a,
    current_phase_2_a,
    current_phase_3_a,
    frequency_hz,
    power_factor_phase_1,
    power_factor_phase_2,
    power_factor_phase_3,
    power_factor_average,
    active_power_phase_1_kw,
    active_power_phase_2_kw,
    active_power_phase_3_kw,
    active_power_total_kw,
    apparent_power_phase_1_kva,
    apparent_power_phase_2_kva,
    apparent_power_phase_3_kva,
    apparent_power_total_kva,
    reactive_power_phase_1_kvar,
    reactive_power_phase_2_kvar,
    reactive_power_phase_3_kvar,
    reactive_power_total_kvar,
    status_vn1,
    status_vn2,
    status_vn3,
    status_v1,
    status_v2,
    status_v3,
    status_amp1,
    status_amp2,
    status_amp3,
    status_hz,
    status_pf1,
    status_pf2,
    status_pf3,
    status_pfa,
    status_kwh,
    overall_status
   FROM silver.fact_energy_readings_snapshot;


--
-- Name: energy_reading_gaps; Type: TABLE; Schema: gold; Owner: -
--

CREATE TABLE gold.energy_reading_gaps (
    energy_meter_key uuid,
    meter_label text COLLATE pg_catalog."C",
    previous_reading_timestamp timestamp without time zone,
    current_reading_timestamp timestamp without time zone,
    gap_seconds numeric,
    gap_minutes numeric,
    gap_hours numeric,
    gap_days numeric
);


--
-- Name: addresses_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.addresses_landing AS
 SELECT id,
    ((short_address)::text COLLATE "C") AS short_address,
    building_number,
    ((street_name)::text COLLATE "C") AS street_name,
    ((district_name)::text COLLATE "C") AS district_name,
    ((city_name)::text COLLATE "C") AS city_name,
    zip_code,
    additional_number,
    unit_number,
    created_on,
    created_by,
    ((title)::text COLLATE "C") AS title
   FROM bronze.addresses;


--
-- Name: VIEW addresses_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.addresses_landing IS 'Landing view for bronze.addresses. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: facilities_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.facilities_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    unit_id,
    facility_type_id,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    address_id,
    created_on,
    created_by
   FROM bronze.facilities;


--
-- Name: VIEW facilities_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.facilities_landing IS 'Landing view for bronze.facilities. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: facilities_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.facilities_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    created_on,
    created_by
   FROM bronze.facilities_types;


--
-- Name: VIEW facilities_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.facilities_types_landing IS 'Landing view for bronze.facilities_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: dim_facility_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.dim_facility_staging AS
 SELECT f.id AS facility_key,
    f.name AS facility_name,
    f.facility_type_id AS facility_type_key,
    ft.name AS facility_type_name,
    f.latitude,
    f.longitude,
    f.x_coordinate,
    f.y_coordinate,
    f.address_id AS address_key,
    a.title AS address_title,
    a.short_address,
    a.building_number,
    a.street_name,
    a.district_name,
    a.city_name,
    a.zip_code,
    a.additional_number,
    a.unit_number,
    f.created_on AS source_created_at
   FROM ((silver.facilities_landing f
     LEFT JOIN silver.facilities_types_landing ft ON ((ft.id = f.facility_type_id)))
     LEFT JOIN silver.addresses_landing a ON ((a.id = f.address_id)));


--
-- Name: VIEW dim_facility_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.dim_facility_staging IS 'Facility dimension enriched with facility type and address attributes.';


--
-- Name: facility; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.facility AS
 SELECT facility_key,
    facility_name,
    facility_type_key,
    facility_type_name,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    address_key,
    address_title,
    short_address,
    building_number,
    street_name,
    district_name,
    city_name,
    zip_code,
    additional_number,
    unit_number,
    source_created_at
   FROM silver.dim_facility_staging;


--
-- Name: device_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    gateway_id,
    ((label)::text COLLATE "C") AS label,
    (user_conf)::jsonb AS user_conf,
    ((description)::text COLLATE "C") AS description,
    type_id,
    unit_id,
    created_on,
    created_by,
    facility_id,
    online,
    client_id,
    assembly_date,
    serial_number,
    label_id,
    properties
   FROM bronze.device;


--
-- Name: VIEW device_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_landing IS 'Landing view for bronze.device. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: energy_meters_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_meters_landing AS
 SELECT id,
    facility_id,
    grid_billing_account_id,
    device_id,
    phase,
    parent_id,
    maximum_kwh,
    type_id,
    unit_id,
    active,
    created_by,
    created_on,
    ((meter_sn)::text COLLATE "C") AS meter_sn,
    ((meter_label)::text COLLATE "C") AS meter_label
   FROM bronze.energy_meters;


--
-- Name: VIEW energy_meters_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.energy_meters_landing IS 'Landing view for bronze.energy_meters. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.units_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    is_building,
    level,
    parent_id,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    type_id,
    active,
    has_children,
    icon_id,
    ((html_hex_color)::text COLLATE "C") AS html_hex_color,
    (description COLLATE "C") AS description,
    created_on,
    created_by,
    facility_id
   FROM bronze.units;


--
-- Name: VIEW units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.units_landing IS 'Landing view for bronze.units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: energy_meter_mapping_audit_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_meter_mapping_audit_staging AS
 WITH source_mapping AS (
         SELECT em.id AS source_energy_meter_id,
            em.device_id,
            em.facility_id,
            em.unit_id AS zone_key,
            u.name AS zone_name,
            d.name AS source_device_name,
            em.meter_label AS source_meter_label,
            em.active AS is_meter_active,
            em.created_on AS meter_source_created_at,
            count(*) OVER (PARTITION BY em.device_id) AS source_meter_records_for_device,
            count(*) OVER (PARTITION BY COALESCE(NULLIF(lower(btrim(em.meter_label)), ''::text), (em.id)::text)) AS source_records_for_meter_label
           FROM ((silver.energy_meters_landing em
             JOIN silver.device_landing d ON ((d.id = em.device_id)))
             LEFT JOIN silver.units_landing u ON ((u.id = em.unit_id)))
        ), business_rules AS (
         SELECT sm.source_energy_meter_id,
            sm.device_id,
            sm.facility_id,
            sm.zone_key,
            sm.zone_name,
            sm.source_device_name,
            sm.source_meter_label,
            sm.is_meter_active,
            sm.meter_source_created_at,
            sm.source_meter_records_for_device,
            sm.source_records_for_meter_label,
            (
                CASE
                    WHEN ((sm.zone_name = 'Zone 03'::text) AND (sm.source_device_name = 'ZN.3-PB_child__1_ch3pm'::text) AND (sm.source_meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text)) THEN 'ZN.3-PB.1_child__1_ch3pm'::text
                    ELSE sm.source_device_name
                END COLLATE "C") AS canonical_device_name,
            (sm.source_meter_label COLLATE "C") AS canonical_meter_label,
            (
                CASE
                    WHEN ((sm.zone_name = 'Zone 03'::text) AND (sm.source_device_name = 'ZN.3-PB_child__1_ch3pm'::text) AND (sm.source_meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text)) THEN 'ZONE03_TEAM_CONFIRMED_DEVICE_NAME_CORRECTION'::text
                    WHEN ((sm.zone_name = 'Zone 13'::text) AND (sm.source_device_name = 'ZN.13-PB.1_child__2_ch3pm'::text) AND (sm.source_meter_label = 'ZN.13-PB.2_child__1_ch3pm'::text)) THEN 'ZONE13_TEAM_CONFIRMED_ONE_PANEL_TWO_METERS'::text
                    WHEN ((sm.zone_name = 'Zone 20'::text) AND (sm.source_device_name = 'ZN.20-PB.1_child__1_ch3pm'::text) AND (sm.source_meter_label = 'ZN.20-PB.2_child__1_ch3pm'::text)) THEN 'ZONE20_TEAM_CONFIRMED_DUPLICATE_TO_EXCLUDE'::text
                    WHEN ((sm.zone_name = 'Zone 20'::text) AND (sm.source_device_name = sm.source_meter_label)) THEN 'ZONE20_TEAM_CONFIRMED_CANONICAL_MAPPING'::text
                    ELSE 'GENERAL_MAPPING_RULE'::text
                END COLLATE "C") AS business_rule_code,
                CASE
                    WHEN ((sm.zone_name = 'Zone 20'::text) AND (sm.source_device_name = 'ZN.20-PB.1_child__1_ch3pm'::text) AND (sm.source_meter_label = 'ZN.20-PB.2_child__1_ch3pm'::text)) THEN 100
                    WHEN ((sm.zone_name = 'Zone 20'::text) AND (sm.source_device_name = sm.source_meter_label)) THEN 0
                    WHEN (lower(btrim(COALESCE(sm.source_meter_label, ''::text))) = lower(btrim(COALESCE(sm.source_device_name, ''::text)))) THEN 10
                    ELSE 20
                END AS business_priority
           FROM source_mapping sm
        ), ranked AS (
         SELECT br.source_energy_meter_id,
            br.device_id,
            br.facility_id,
            br.zone_key,
            br.zone_name,
            br.source_device_name,
            br.source_meter_label,
            br.is_meter_active,
            br.meter_source_created_at,
            br.source_meter_records_for_device,
            br.source_records_for_meter_label,
            br.canonical_device_name,
            br.canonical_meter_label,
            br.business_rule_code,
            br.business_priority,
            row_number() OVER (PARTITION BY br.device_id ORDER BY br.business_priority, br.is_meter_active DESC, br.meter_source_created_at, br.source_energy_meter_id) AS canonical_mapping_rank
           FROM business_rules br
        )
 SELECT source_energy_meter_id,
    device_id,
    facility_id,
    zone_key,
    zone_name,
    source_device_name,
    source_meter_label,
    canonical_device_name,
    canonical_meter_label,
    source_meter_records_for_device,
    source_records_for_meter_label,
    business_rule_code,
    canonical_mapping_rank,
    (
        CASE
            WHEN (business_rule_code = 'ZONE20_TEAM_CONFIRMED_DUPLICATE_TO_EXCLUDE'::text) THEN 'EXCLUDE'::text
            WHEN (canonical_mapping_rank = 1) THEN 'KEEP'::text
            ELSE 'EXCLUDE'::text
        END COLLATE "C") AS mapping_decision,
    (
        CASE
            WHEN (business_rule_code = 'ZONE03_TEAM_CONFIRMED_DEVICE_NAME_CORRECTION'::text) THEN 'TEAM_CONFIRMED_NAME_CORRECTION'::text
            WHEN (business_rule_code = 'ZONE13_TEAM_CONFIRMED_ONE_PANEL_TWO_METERS'::text) THEN 'TEAM_CONFIRMED_EXCEPTION_ONE_PANEL_TWO_METERS'::text
            WHEN ((zone_name = 'Zone 20'::text) AND (canonical_mapping_rank = 1)) THEN 'TEAM_CONFIRMED_DUPLICATE_MAPPING_RESOLVED'::text
            WHEN (canonical_mapping_rank <> 1) THEN 'EXCLUDED_NON_CANONICAL_MAPPING'::text
            WHEN ((source_meter_records_for_device = 1) AND (source_records_for_meter_label = 1) AND (lower(btrim(COALESCE(source_meter_label, ''::text))) = lower(btrim(COALESCE(source_device_name, ''::text))))) THEN 'VALID'::text
            WHEN ((source_meter_records_for_device = 1) AND (source_records_for_meter_label = 1)) THEN 'REVIEW_NAME_MISMATCH'::text
            WHEN (lower(btrim(COALESCE(source_meter_label, ''::text))) = lower(btrim(COALESCE(source_device_name, ''::text)))) THEN 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_NAME_MATCH'::text
            ELSE 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_SELECTED'::text
        END COLLATE "C") AS mapping_status,
    is_meter_active,
    meter_source_created_at
   FROM ranked;


--
-- Name: mapping_audit; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.mapping_audit AS
 SELECT source_energy_meter_id,
    device_id,
    facility_id,
    zone_key,
    zone_name,
    source_device_name,
    source_meter_label,
    canonical_device_name,
    canonical_meter_label,
    source_meter_records_for_device,
    source_records_for_meter_label,
    business_rule_code,
    canonical_mapping_rank,
    mapping_decision,
    mapping_status,
    is_meter_active,
    meter_source_created_at
   FROM silver.energy_meter_mapping_audit_staging;


--
-- Name: devices_categories_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.devices_categories_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((code)::text COLLATE "C") AS code,
    created_on
   FROM bronze.devices_categories;


--
-- Name: VIEW devices_categories_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.devices_categories_landing IS 'Landing view for bronze.devices_categories. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: devices_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.devices_types_landing AS
 SELECT id,
    category_id,
    ((name)::text COLLATE "C") AS name,
    (config_preset)::jsonb AS config_preset,
    created_on,
    created_by,
    code,
    (description COLLATE "C") AS description,
    ((icon)::text COLLATE "C") AS icon,
    properties
   FROM bronze.devices_types;


--
-- Name: VIEW devices_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.devices_types_landing IS 'Landing view for bronze.devices_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: energy_meters_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_meters_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    created_on
   FROM bronze.energy_meters_types;


--
-- Name: VIEW energy_meters_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.energy_meters_types_landing IS 'Landing view for bronze.energy_meters_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: dim_energy_meter_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.dim_energy_meter_staging AS
 WITH ranked_mapping AS (
         SELECT d.id AS energy_meter_key,
            em.id AS source_energy_meter_id,
            em.facility_id AS facility_key,
            em.unit_id AS zone_key,
            em.grid_billing_account_id AS grid_billing_account_key,
            em.parent_id AS parent_energy_meter_source_id,
            em.meter_label AS source_meter_label,
            d.name AS source_device_name,
            u.name AS zone_name,
            em.meter_sn AS meter_serial_number,
            em.phase AS phase_count,
            em.maximum_kwh,
            em.type_id AS energy_meter_type_key,
            emt.name AS energy_meter_type_name,
            em.active AS is_meter_active,
            em.created_on AS meter_source_created_at,
            d.label AS device_label,
            d.serial_number AS device_serial_number,
            d.type_id AS device_type_key,
            dt.name AS device_type_name,
            dt.category_id AS device_category_key,
            dc.name AS device_category_name,
            d.gateway_id,
            d.active AS is_device_active,
            d.online AS is_device_online,
            d.assembly_date,
            d.properties AS device_properties,
            count(*) OVER (PARTITION BY em.device_id) AS source_meter_records_for_device,
            count(*) OVER (PARTITION BY COALESCE(NULLIF(lower(btrim(em.meter_label)), ''::text), (em.id)::text)) AS source_records_for_meter_label,
            (lower(btrim(COALESCE(em.meter_label, ''::text))) = lower(btrim(COALESCE(d.name, ''::text)))) AS source_meter_label_matches_device_name,
            (
                CASE
                    WHEN ((u.name = 'Zone 03'::text) AND (d.name = 'ZN.3-PB_child__1_ch3pm'::text) AND (em.meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text)) THEN 'ZN.3-PB.1_child__1_ch3pm'::text
                    ELSE d.name
                END COLLATE "C") AS canonical_device_name,
            (em.meter_label COLLATE "C") AS canonical_meter_label,
            row_number() OVER (PARTITION BY em.device_id ORDER BY
                CASE
                    WHEN ((u.name = 'Zone 20'::text) AND (d.name = em.meter_label)) THEN 0
                    WHEN (lower(btrim(COALESCE(em.meter_label, ''::text))) = lower(btrim(COALESCE(d.name, ''::text)))) THEN 10
                    ELSE 20
                END, em.active DESC, em.created_on, em.id) AS canonical_mapping_rank
           FROM (((((silver.energy_meters_landing em
             JOIN silver.device_landing d ON ((d.id = em.device_id)))
             LEFT JOIN silver.units_landing u ON ((u.id = em.unit_id)))
             LEFT JOIN silver.energy_meters_types_landing emt ON ((emt.id = em.type_id)))
             LEFT JOIN silver.devices_types_landing dt ON ((dt.id = d.type_id)))
             LEFT JOIN silver.devices_categories_landing dc ON ((dc.id = dt.category_id)))
          WHERE (NOT ((em.device_id = '9574e049-9fb7-46db-9f8c-b3da0666aea0'::uuid) AND (em.meter_label = 'ZN.20-PB.2_child__1_ch3pm'::text)))
        )
 SELECT energy_meter_key,
    source_energy_meter_id,
    facility_key,
    zone_key,
    grid_billing_account_key,
    parent_energy_meter_source_id,
    canonical_meter_label AS meter_label,
    meter_serial_number,
    phase_count,
    maximum_kwh,
    energy_meter_type_key,
    energy_meter_type_name,
    is_meter_active,
    canonical_device_name AS device_name,
    device_label,
    device_serial_number,
    device_type_key,
    device_type_name,
    device_category_key,
    device_category_name,
    gateway_id,
    is_device_active,
    is_device_online,
    assembly_date,
    device_properties,
    source_meter_records_for_device,
    source_records_for_meter_label,
    (lower(btrim(COALESCE(canonical_meter_label, ''::text))) = lower(btrim(COALESCE(canonical_device_name, ''::text)))) AS meter_label_matches_device_name,
    (
        CASE
            WHEN ((zone_name = 'Zone 03'::text) AND (source_device_name = 'ZN.3-PB_child__1_ch3pm'::text) AND (source_meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text)) THEN 'TEAM_CONFIRMED_NAME_CORRECTION'::text
            WHEN ((zone_name = 'Zone 13'::text) AND (source_device_name = 'ZN.13-PB.1_child__2_ch3pm'::text) AND (source_meter_label = 'ZN.13-PB.2_child__1_ch3pm'::text)) THEN 'TEAM_CONFIRMED_EXCEPTION_ONE_PANEL_TWO_METERS'::text
            WHEN ((source_meter_records_for_device = 1) AND (source_records_for_meter_label = 1) AND source_meter_label_matches_device_name) THEN 'VALID'::text
            WHEN ((source_meter_records_for_device = 1) AND (source_records_for_meter_label = 1)) THEN 'REVIEW_NAME_MISMATCH'::text
            WHEN source_meter_label_matches_device_name THEN 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_NAME_MATCH'::text
            ELSE 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_SELECTED'::text
        END COLLATE "C") AS mapping_status,
    meter_source_created_at
   FROM ranked_mapping
  WHERE (canonical_mapping_rank = 1);


--
-- Name: VIEW dim_energy_meter_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.dim_energy_meter_staging IS 'Canonical energy-meter/device dimension. One row per reporting device; duplicate source mappings remain flagged.';


--
-- Name: meter; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.meter AS
 SELECT energy_meter_key,
    source_energy_meter_id,
    facility_key,
    zone_key,
    grid_billing_account_key,
    parent_energy_meter_source_id,
    meter_label,
    meter_serial_number,
    phase_count,
    maximum_kwh,
    energy_meter_type_key,
    energy_meter_type_name,
    is_meter_active,
    device_name,
    device_label,
    device_serial_number,
    device_type_key,
    device_type_name,
    device_category_key,
    device_category_name,
    gateway_id,
    is_device_active,
    is_device_online,
    assembly_date,
    device_properties,
    source_meter_records_for_device,
    source_records_for_meter_label,
    meter_label_matches_device_name,
    mapping_status,
    meter_source_created_at
   FROM silver.dim_energy_meter_staging;


--
-- Name: data_quality_summary; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.data_quality_summary (
    energy_meter_key uuid NOT NULL,
    meter_label text,
    total_readings integer,
    overall_acceptable_count integer,
    overall_review_required_count integer,
    overall_anomaly_count integer,
    overall_problematic_count integer,
    overall_critical_count integer,
    overall_invalid_count integer,
    computed_at timestamp without time zone DEFAULT now()
);


--
-- Name: quality_summary; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.quality_summary AS
 SELECT energy_meter_key,
    meter_label,
    total_readings,
    overall_acceptable_count,
    overall_review_required_count,
    overall_anomaly_count,
    overall_problematic_count,
    overall_critical_count,
    overall_invalid_count,
    computed_at
   FROM silver.data_quality_summary;


--
-- Name: units_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.units_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    (description COLLATE "C") AS description,
    global_type,
    default_level,
    default_type_for_its_level,
    icon_id,
    created_on,
    created_by,
    facility_id
   FROM bronze.units_types;


--
-- Name: VIEW units_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.units_types_landing IS 'Landing view for bronze.units_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: dim_zone_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.dim_zone_staging AS
 SELECT u.id AS zone_key,
    u.facility_id AS facility_key,
    u.parent_id AS parent_zone_key,
    parent_u.name AS parent_zone_name,
    u.name AS zone_name,
    u.type_id AS zone_type_key,
    ut.name AS zone_type_name,
    u.level AS hierarchy_level,
    u.is_building,
    u.active AS is_active,
    u.has_children,
    u.latitude,
    u.longitude,
    u.x_coordinate,
    u.y_coordinate,
    u.html_hex_color,
    u.description,
    u.created_on AS source_created_at
   FROM ((silver.units_landing u
     LEFT JOIN silver.units_landing parent_u ON ((parent_u.id = u.parent_id)))
     LEFT JOIN silver.units_types_landing ut ON ((ut.id = u.type_id)));


--
-- Name: VIEW dim_zone_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.dim_zone_staging IS 'Zone/unit dimension containing facility and parent-child hierarchy keys.';


--
-- Name: zone; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.zone AS
 SELECT zone_key,
    facility_key,
    parent_zone_key,
    parent_zone_name,
    zone_name,
    zone_type_key,
    zone_type_name,
    hierarchy_level,
    is_building,
    is_active,
    has_children,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    html_hex_color,
    description,
    source_created_at
   FROM silver.dim_zone_staging;


--
-- Name: agg_energy_1d; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_1d (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    loaded_at timestamp without time zone DEFAULT now(),
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text
);


--
-- Name: agg_energy_1h; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_1h (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    loaded_at timestamp without time zone DEFAULT now(),
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text
);


--
-- Name: agg_energy_1month; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_1month (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text,
    loaded_at timestamp without time zone DEFAULT now()
);


--
-- Name: agg_energy_1week; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_1week (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text,
    loaded_at timestamp without time zone DEFAULT now()
);


--
-- Name: agg_energy_30min; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_30min (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    loaded_at timestamp without time zone DEFAULT now(),
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text
);


--
-- Name: agg_energy_3d; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_3d (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text,
    loaded_at timestamp without time zone DEFAULT now()
);


--
-- Name: agg_energy_4h; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_4h (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    loaded_at timestamp without time zone DEFAULT now(),
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text
);


--
-- Name: alarm_acknowledgement_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_acknowledgement_types_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title
   FROM bronze.alarm_acknowledgement_types;


--
-- Name: VIEW alarm_acknowledgement_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_acknowledgement_types_landing IS 'Landing view for bronze.alarm_acknowledgement_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_acknowledgements_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_acknowledgements_landing AS
 SELECT id,
    alarm_configuration_id,
    device_id,
    acknowledged_until,
    "timestamp",
    acknowledged_by
   FROM bronze.alarm_acknowledgements;


--
-- Name: VIEW alarm_acknowledgements_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_acknowledgements_landing IS 'Landing view for bronze.alarm_acknowledgements. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_configurations_history_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_configurations_history_landing AS
 SELECT id,
    (payload)::jsonb AS payload,
    alarm_configuration_id,
    created_by,
    updated_by,
    updated_at
   FROM bronze.alarm_configurations_history;


--
-- Name: VIEW alarm_configurations_history_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_configurations_history_landing IS 'Landing view for bronze.alarm_configurations_history. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_configurations_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_configurations_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title,
    ((description)::text COLLATE "C") AS description,
    (details)::jsonb AS details,
    severity_id,
    alarm_type_id,
    created_on,
    created_by,
    active
   FROM bronze.alarm_configurations;


--
-- Name: VIEW alarm_configurations_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_configurations_landing IS 'Landing view for bronze.alarm_configurations. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_contact_groups_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_contact_groups_landing AS
 SELECT alarm_configuration_id,
    contact_label_id,
    contact_after,
    level
   FROM bronze.alarm_contact_groups;


--
-- Name: VIEW alarm_contact_groups_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_contact_groups_landing IS 'Landing view for bronze.alarm_contact_groups. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_contact_methods_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_contact_methods_landing AS
 SELECT contact_after,
    notification_interval,
    contact_method_id,
    alarm_configuration_id
   FROM bronze.alarm_contact_methods;


--
-- Name: VIEW alarm_contact_methods_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_contact_methods_landing IS 'Landing view for bronze.alarm_contact_methods. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_contacts_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_contacts_landing AS
 SELECT alarm_configuration_id,
    level,
    contact_after,
    contact_id
   FROM bronze.alarm_contacts;


--
-- Name: VIEW alarm_contacts_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_contacts_landing IS 'Landing view for bronze.alarm_contacts. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_device_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_device_landing AS
 SELECT device_id,
    alarm_level_id,
    alarm_configuration_id,
    active
   FROM bronze.alarm_device;


--
-- Name: VIEW alarm_device_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_device_landing IS 'Landing view for bronze.alarm_device. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_device_mapping_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_device_mapping_landing AS
 SELECT alarm_configuration_id,
    device_type_id,
    device_category_id,
    alarm_level_id,
    unit_id
   FROM bronze.alarm_device_mapping;


--
-- Name: VIEW alarm_device_mapping_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_device_mapping_landing IS 'Landing view for bronze.alarm_device_mapping. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_levels_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_levels_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title,
    ((description)::text COLLATE "C") AS description
   FROM bronze.alarm_levels;


--
-- Name: VIEW alarm_levels_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_levels_landing IS 'Landing view for bronze.alarm_levels. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_log_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_log_types_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title
   FROM bronze.alarm_log_types;


--
-- Name: VIEW alarm_log_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_log_types_landing IS 'Landing view for bronze.alarm_log_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_logs_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_logs_landing AS
 SELECT (details)::jsonb AS details,
    alarm_configuration_id,
    log_type_id,
    device_id,
    "timestamp"
   FROM bronze.alarm_logs;


--
-- Name: VIEW alarm_logs_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_logs_landing IS 'Landing view for bronze.alarm_logs. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_notifications_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_notifications_landing AS
 SELECT alarm_configuration_id,
    device_id,
    notification_id
   FROM bronze.alarm_notifications;


--
-- Name: VIEW alarm_notifications_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_notifications_landing IS 'Landing view for bronze.alarm_notifications. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_telemetry_keys_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_telemetry_keys_landing AS
 SELECT alarm_configuration_id,
    telemetry_key_id,
    (details)::jsonb AS details
   FROM bronze.alarm_telemetry_keys;


--
-- Name: VIEW alarm_telemetry_keys_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_telemetry_keys_landing IS 'Landing view for bronze.alarm_telemetry_keys. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_types_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title,
    ((description)::text COLLATE "C") AS description,
    created_on,
    active
   FROM bronze.alarm_types;


--
-- Name: VIEW alarm_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_types_landing IS 'Landing view for bronze.alarm_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarms_severities_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarms_severities_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    ((icon)::text COLLATE "C") AS icon,
    ((hex_color)::text COLLATE "C") AS hex_color,
    (default_configs)::jsonb AS default_configs,
    created_on,
    created_by
   FROM bronze.alarms_severities;


--
-- Name: VIEW alarms_severities_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarms_severities_landing IS 'Landing view for bronze.alarms_severities. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarms_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarms_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    created_on
   FROM bronze.alarms_types;


--
-- Name: VIEW alarms_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarms_types_landing IS 'Landing view for bronze.alarms_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: appliance_category_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.appliance_category_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((icon)::text COLLATE "C") AS icon,
    created_on
   FROM bronze.appliance_category;


--
-- Name: VIEW appliance_category_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.appliance_category_landing IS 'Landing view for bronze.appliance_category. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: appliances_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.appliances_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    category_id,
    unit_id,
    meter_id,
    facility_id,
    created_on,
    created_by
   FROM bronze.appliances;


--
-- Name: VIEW appliances_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.appliances_landing IS 'Landing view for bronze.appliances. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: attempted_logins_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.attempted_logins_landing AS
 SELECT id,
    user_id,
    ((ip_address)::text COLLATE "C") AS ip_address,
    is_successful,
    ((details)::text COLLATE "C") AS details,
    created_on
   FROM bronze.attempted_logins;


--
-- Name: VIEW attempted_logins_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.attempted_logins_landing IS 'Landing view for bronze.attempted_logins. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: banned_jtis_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.banned_jtis_landing AS
 SELECT id,
    refresh_token_jti,
    user_id,
    created_on
   FROM bronze.banned_jtis;


--
-- Name: VIEW banned_jtis_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.banned_jtis_landing IS 'Landing view for bronze.banned_jtis. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: budget_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.budget_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    created_on
   FROM bronze.budget_types;


--
-- Name: VIEW budget_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.budget_types_landing IS 'Landing view for bronze.budget_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: budgets_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.budgets_landing AS
 SELECT id,
    value,
    type_id,
    facility_id,
    created_by,
    created_on
   FROM bronze.budgets;


--
-- Name: VIEW budgets_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.budgets_landing IS 'Landing view for bronze.budgets. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: clients_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.clients_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((code)::text COLLATE "C") AS code,
    facility_id,
    created_on
   FROM bronze.clients;


--
-- Name: VIEW clients_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.clients_landing IS 'Landing view for bronze.clients. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: consumption_categories_grid_billing_accounts_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.consumption_categories_grid_billing_accounts_types_landing AS
 SELECT consumption_category_id,
    grid_billing_account_type_id,
    fee_per_kwh,
    created_by,
    created_on
   FROM bronze.consumption_categories_grid_billing_accounts_types;


--
-- Name: VIEW consumption_categories_grid_billing_accounts_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.consumption_categories_grid_billing_accounts_types_landing IS 'Landing view for bronze.consumption_categories_grid_billing_accounts_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: consumption_categories_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.consumption_categories_landing AS
 SELECT id,
    facility_id,
    ((name)::text COLLATE "C") AS name,
    maximum_kwh,
    minimum_kwh,
    active,
    created_by,
    created_on
   FROM bronze.consumption_categories;


--
-- Name: VIEW consumption_categories_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.consumption_categories_landing IS 'Landing view for bronze.consumption_categories. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: contact_labels_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.contact_labels_landing AS
 SELECT contact_id,
    label_id
   FROM bronze.contact_labels;


--
-- Name: VIEW contact_labels_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.contact_labels_landing IS 'Landing view for bronze.contact_labels. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: contact_method_mapping_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.contact_method_mapping_landing AS
 SELECT contact_id,
    contact_method_id
   FROM bronze.contact_method_mapping;


--
-- Name: VIEW contact_method_mapping_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.contact_method_mapping_landing IS 'Landing view for bronze.contact_method_mapping. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: contact_methods_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.contact_methods_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title,
    ((description)::text COLLATE "C") AS description,
    created_on
   FROM bronze.contact_methods;


--
-- Name: VIEW contact_methods_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.contact_methods_landing IS 'Landing view for bronze.contact_methods. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: contacts_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.contacts_landing AS
 SELECT id,
    ((full_name)::text COLLATE "C") AS full_name,
    ((description)::text COLLATE "C") AS description,
    (preferences)::jsonb AS preferences,
    user_id,
    ((email)::text COLLATE "C") AS email,
    ((phone_number)::text COLLATE "C") AS phone_number,
    created_on,
    created_by
   FROM bronze.contacts;


--
-- Name: VIEW contacts_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.contacts_landing IS 'Landing view for bronze.contacts. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: deleted_schedules_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.deleted_schedules_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    (description COLLATE "C") AS description,
    start_datetime,
    end_datetime,
    schedule_duration,
    triggers,
    active,
    created_on,
    created_by,
    deleted_by,
    deleted_at,
    deleted_schedule_units,
    deleted_schedule_controllers
   FROM bronze.deleted_schedules;


--
-- Name: VIEW deleted_schedules_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.deleted_schedules_landing IS 'Landing view for bronze.deleted_schedules. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_control_labels_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_control_labels_landing AS
 SELECT device_control_id,
    label_id,
    created_by,
    created_on
   FROM bronze.device_control_labels;


--
-- Name: VIEW device_control_labels_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_control_labels_landing IS 'Landing view for bronze.device_control_labels. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_control_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_control_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name
   FROM bronze.device_control_types;


--
-- Name: VIEW device_control_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_control_types_landing IS 'Landing view for bronze.device_control_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_controls_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_controls_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    device_id,
    unit_id,
    ((icon)::text COLLATE "C") AS icon,
    ((icon_color)::text COLLATE "C") AS icon_color,
    config,
    created_by,
    ((telemetry_key)::text COLLATE "C") AS telemetry_key,
    (description COLLATE "C") AS description
   FROM bronze.device_controls;


--
-- Name: VIEW device_controls_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_controls_landing IS 'Landing view for bronze.device_controls. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_controls_unit_pinned_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_controls_unit_pinned_landing AS
 SELECT id,
    user_id,
    unit_id,
    pinned,
    visible
   FROM bronze.device_controls_unit_pinned;


--
-- Name: VIEW device_controls_unit_pinned_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_controls_unit_pinned_landing IS 'Landing view for bronze.device_controls_unit_pinned. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_credentials_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_credentials_landing AS
 SELECT ((cred_id)::text COLLATE "C") AS cred_id,
    device_id,
    ((cred_val)::text COLLATE "C") AS cred_val,
    ((cred_type)::text COLLATE "C") AS cred_type,
    ((extra_credentials)::text COLLATE "C") AS extra_credentials,
    created_on,
    ((username)::text COLLATE "C") AS username,
    ((uudid)::text COLLATE "C") AS uudid
   FROM bronze.device_credentials;


--
-- Name: VIEW device_credentials_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_credentials_landing IS 'Landing view for bronze.device_credentials. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_sensors_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_sensors_landing AS
 SELECT device_id,
    sensor_id,
    ((telemetry_key)::text COLLATE "C") AS telemetry_key,
    telemetry_key_id,
    control_id,
    ((category_name)::text COLLATE "C") AS category_name,
    created_on,
    created_by
   FROM bronze.device_sensors;


--
-- Name: VIEW device_sensors_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_sensors_landing IS 'Landing view for bronze.device_sensors. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_time_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_time_landing AS
 SELECT device_id,
    "timestamp",
    online,
        CASE
            WHEN (value IS NULL) THEN NULL::double precision
            ELSE (round((value)::numeric, 9))::double precision
        END AS value,
    ((telemetry_key_name)::text COLLATE "C") AS telemetry_key_name,
    on_time,
    off_time,
    run_time
   FROM bronze.device_time;


--
-- Name: VIEW device_time_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_time_landing IS 'Landing view for bronze.device_time. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: dim_meter_cb_rating; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.dim_meter_cb_rating (
    energy_meter_key uuid NOT NULL,
    cb_max_rating_a double precision NOT NULL,
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: dq_device_cadence_staging; Type: MATERIALIZED VIEW; Schema: silver; Owner: -
--

CREATE MATERIALIZED VIEW silver.dq_device_cadence_staging AS
 WITH tkw_readings AS (
         SELECT t.device_id,
            t."timestamp",
            lag(t."timestamp") OVER (PARTITION BY t.device_id ORDER BY t."timestamp") AS previous_timestamp
           FROM ((bronze.telemetries t
             JOIN bronze.telemetries_dictionaries td ON (((td.id = t.key_id) AND ((td.key)::text = 'TkW'::text))))
             JOIN silver.dim_energy_meter_staging m ON ((m.energy_meter_key = t.device_id)))
        ), reading_coverage AS (
         SELECT t.device_id,
            count(*) AS total_tkw_reading_count,
            min(t."timestamp") AS first_timestamp_ms,
            max(t."timestamp") AS last_timestamp_ms,
            (count(DISTINCT ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date))::integer AS days_with_tkw_data
           FROM tkw_readings t
          GROUP BY t.device_id
        ), all_gaps AS (
         SELECT tkw_readings.device_id,
            tkw_readings."timestamp",
            tkw_readings.previous_timestamp,
            (((tkw_readings."timestamp" - tkw_readings.previous_timestamp))::numeric / 1000.0) AS gap_seconds
           FROM tkw_readings
          WHERE (tkw_readings.previous_timestamp IS NOT NULL)
        ), cadence_candidates AS (
         SELECT all_gaps.device_id,
            all_gaps."timestamp",
            all_gaps.previous_timestamp,
            all_gaps.gap_seconds
           FROM all_gaps
          WHERE ((all_gaps.gap_seconds >= (30)::numeric) AND (all_gaps.gap_seconds <= (1800)::numeric))
        ), cadence_statistics AS (
         SELECT cadence_candidates.device_id,
            count(*) AS baseline_interval_count,
            percentile_cont((0.10)::double precision) WITHIN GROUP (ORDER BY ((cadence_candidates.gap_seconds)::double precision)) AS p10_gap_seconds,
            percentile_cont((0.50)::double precision) WITHIN GROUP (ORDER BY ((cadence_candidates.gap_seconds)::double precision)) AS observed_gap_seconds,
            percentile_cont((0.90)::double precision) WITHIN GROUP (ORDER BY ((cadence_candidates.gap_seconds)::double precision)) AS p90_gap_seconds,
            avg(cadence_candidates.gap_seconds) AS average_candidate_gap_seconds,
            stddev_samp(cadence_candidates.gap_seconds) AS candidate_gap_stddev_seconds
           FROM cadence_candidates
          GROUP BY cadence_candidates.device_id
        ), gap_totals AS (
         SELECT all_gaps.device_id,
            count(*) AS all_interval_count,
            count(*) FILTER (WHERE (all_gaps.gap_seconds > (1800)::numeric)) AS gap_over_30_minutes_count,
            max(all_gaps.gap_seconds) AS maximum_observed_gap_seconds
           FROM all_gaps
          GROUP BY all_gaps.device_id
        ), cadence_base AS (
         SELECT m.energy_meter_key,
            m.source_energy_meter_id,
            m.facility_key,
            m.zone_key,
            z.zone_name,
            m.device_name,
            m.meter_label,
            m.gateway_id,
            m.mapping_status,
            rc.total_tkw_reading_count,
            rc.days_with_tkw_data,
            rc.first_timestamp_ms,
            rc.last_timestamp_ms,
            cs.baseline_interval_count,
            gt.all_interval_count,
            cs.p10_gap_seconds,
            cs.observed_gap_seconds,
            cs.p90_gap_seconds,
            cs.average_candidate_gap_seconds,
            cs.candidate_gap_stddev_seconds,
            COALESCE(gt.gap_over_30_minutes_count, (0)::bigint) AS gap_over_30_minutes_count,
            gt.maximum_observed_gap_seconds
           FROM ((((silver.dim_energy_meter_staging m
             JOIN silver.dim_zone_staging z ON ((z.zone_key = m.zone_key)))
             LEFT JOIN reading_coverage rc ON ((rc.device_id = m.energy_meter_key)))
             LEFT JOIN cadence_statistics cs ON ((cs.device_id = m.energy_meter_key)))
             LEFT JOIN gap_totals gt ON ((gt.device_id = m.energy_meter_key)))
        )
 SELECT energy_meter_key,
    source_energy_meter_id,
    facility_key,
    zone_key,
    zone_name,
    device_name,
    meter_label,
    gateway_id,
    mapping_status,
    total_tkw_reading_count,
    days_with_tkw_data,
        CASE
            WHEN (first_timestamp_ms IS NULL) THEN NULL::timestamp without time zone
            ELSE (to_timestamp((((first_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text)
        END AS first_reading_utc,
        CASE
            WHEN (last_timestamp_ms IS NULL) THEN NULL::timestamp without time zone
            ELSE (to_timestamp((((last_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text)
        END AS last_reading_utc,
        CASE
            WHEN (first_timestamp_ms IS NULL) THEN NULL::date
            ELSE ((to_timestamp((((first_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date
        END AS first_reading_date,
        CASE
            WHEN (last_timestamp_ms IS NULL) THEN NULL::date
            ELSE ((to_timestamp((((last_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date
        END AS last_reading_date,
    baseline_interval_count,
    all_interval_count,
    round((p10_gap_seconds)::numeric, 3) AS p10_gap_seconds,
    300.000 AS nominal_gap_seconds,
    5.000 AS nominal_gap_minutes,
    288 AS nominal_expected_daily_reading_count,
    round((observed_gap_seconds)::numeric, 3) AS observed_gap_seconds,
    round(((observed_gap_seconds / (60.0)::double precision))::numeric, 3) AS observed_gap_minutes,
        CASE
            WHEN (observed_gap_seconds IS NULL) THEN NULL::integer
            ELSE (round(((86400.0)::double precision / observed_gap_seconds)))::integer
        END AS observed_expected_daily_reading_count,
    round((observed_gap_seconds)::numeric, 3) AS expected_gap_seconds,
    round(((observed_gap_seconds / (60.0)::double precision))::numeric, 3) AS expected_gap_minutes,
        CASE
            WHEN (observed_gap_seconds IS NULL) THEN NULL::integer
            ELSE (round(((86400.0)::double precision / observed_gap_seconds)))::integer
        END AS expected_daily_reading_count,
    round((p90_gap_seconds)::numeric, 3) AS p90_gap_seconds,
    round(((p90_gap_seconds - p10_gap_seconds))::numeric, 3) AS cadence_spread_seconds,
    round(average_candidate_gap_seconds, 3) AS average_candidate_gap_seconds,
    round(candidate_gap_stddev_seconds, 3) AS candidate_gap_stddev_seconds,
    round(((observed_gap_seconds - (300.0)::double precision))::numeric, 3) AS variance_from_nominal_seconds,
    round(((((observed_gap_seconds - (300.0)::double precision) / (300.0)::double precision))::numeric * (100)::numeric), 3) AS variance_from_nominal_percent,
    gap_over_30_minutes_count,
    round(maximum_observed_gap_seconds, 3) AS maximum_observed_gap_seconds,
    (
        CASE
            WHEN ((observed_gap_seconds IS NULL) OR (baseline_interval_count < 100)) THEN 'INSUFFICIENT_BASELINE'::text
            WHEN ((p90_gap_seconds - p10_gap_seconds) > (60)::double precision) THEN 'UNSTABLE_CADENCE_REVIEW'::text
            WHEN (abs((observed_gap_seconds - (300)::double precision)) <= (15)::double precision) THEN 'STANDARD_APPROXIMATELY_5_MINUTES'::text
            ELSE 'NON_STANDARD_STABLE_CADENCE'::text
        END COLLATE "C") AS cadence_status,
    (
        CASE
            WHEN ((observed_gap_seconds IS NULL) OR (baseline_interval_count < 100)) THEN 'INSUFFICIENT_BASELINE'::text
            WHEN ((p90_gap_seconds - p10_gap_seconds) > (60)::double precision) THEN 'UNSTABLE_CADENCE_REVIEW'::text
            WHEN (abs((observed_gap_seconds - (300)::double precision)) <= (15)::double precision) THEN 'MEETS_NOMINAL_APPROX_5_MINUTE_CADENCE'::text
            ELSE 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text
        END COLLATE "C") AS nominal_cadence_status,
        CASE
            WHEN ((observed_gap_seconds IS NULL) OR (baseline_interval_count < 100)) THEN false
            WHEN ((p90_gap_seconds - p10_gap_seconds) <= (60)::double precision) THEN true
            ELSE false
        END AS cadence_baseline_is_reliable
   FROM cadence_base
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW dq_device_cadence_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON MATERIALIZED VIEW silver.dq_device_cadence_staging IS 'One row per canonical meter. Stores both the nominal 300-second/288-reading target and each device''s observed historical cadence. Source telemetry is unchanged.';


--
-- Name: COLUMN dq_device_cadence_staging.nominal_expected_daily_reading_count; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_device_cadence_staging.nominal_expected_daily_reading_count IS 'Official nominal full-day target: 288 readings at five-minute cadence.';


--
-- Name: COLUMN dq_device_cadence_staging.observed_expected_daily_reading_count; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_device_cadence_staging.observed_expected_daily_reading_count IS 'Device-specific expected count calculated from the historical median TkW timestamp gap.';


--
-- Name: COLUMN dq_device_cadence_staging.expected_daily_reading_count; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_device_cadence_staging.expected_daily_reading_count IS 'Backward-compatible alias for observed_expected_daily_reading_count.';


--
-- Name: dq_meter_daily_completeness_staging; Type: MATERIALIZED VIEW; Schema: silver; Owner: -
--

CREATE MATERIALIZED VIEW silver.dq_meter_daily_completeness_staging AS
 WITH tkw_readings AS (
         SELECT t.device_id,
            t."timestamp",
            ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date AS reading_date,
            lag(t."timestamp") OVER (PARTITION BY t.device_id, (((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date) ORDER BY t."timestamp") AS previous_timestamp_same_day
           FROM ((bronze.telemetries t
             JOIN bronze.telemetries_dictionaries td ON (((td.id = t.key_id) AND ((td.key)::text = 'TkW'::text))))
             JOIN silver.dq_device_cadence_staging b ON (((b.energy_meter_key = t.device_id) AND b.cadence_baseline_is_reliable)))
        ), daily_observed AS (
         SELECT r.device_id,
            r.reading_date,
            (count(DISTINCT r."timestamp"))::integer AS actual_reading_count,
            min(r."timestamp") AS first_timestamp_ms,
            max(r."timestamp") AS last_timestamp_ms,
            max((((r."timestamp" - r.previous_timestamp_same_day))::numeric / 1000.0)) FILTER (WHERE (r.previous_timestamp_same_day IS NOT NULL)) AS maximum_within_day_gap_seconds
           FROM tkw_readings r
          GROUP BY r.device_id, r.reading_date
        ), daily_large_gaps AS (
         SELECT r.device_id,
            r.reading_date,
            (count(*) FILTER (WHERE ((r.previous_timestamp_same_day IS NOT NULL) AND ((((r."timestamp" - r.previous_timestamp_same_day))::numeric / 1000.0) > (b.observed_gap_seconds * 1.5)))))::integer AS large_gap_count
           FROM (tkw_readings r
             JOIN silver.dq_device_cadence_staging b ON ((b.energy_meter_key = r.device_id)))
          GROUP BY r.device_id, r.reading_date
        ), device_calendar AS (
         SELECT b.energy_meter_key,
            (gs.reading_date)::date AS reading_date
           FROM (silver.dq_device_cadence_staging b
             CROSS JOIN LATERAL generate_series((b.first_reading_date)::timestamp without time zone, (b.last_reading_date)::timestamp without time zone, '1 day'::interval) gs(reading_date))
          WHERE b.cadence_baseline_is_reliable
        ), quality_base AS (
         SELECT b.energy_meter_key,
            b.source_energy_meter_id,
            b.facility_key,
            b.zone_key,
            b.zone_name,
            b.device_name,
            b.meter_label,
            b.gateway_id,
            b.cadence_status,
            b.nominal_cadence_status,
            c.reading_date,
            b.nominal_gap_seconds,
            b.nominal_gap_minutes,
            b.nominal_expected_daily_reading_count,
            b.observed_gap_seconds,
            b.observed_gap_minutes,
            b.observed_expected_daily_reading_count,
            COALESCE(o.actual_reading_count, 0) AS actual_reading_count,
            GREATEST((b.nominal_expected_daily_reading_count - COALESCE(o.actual_reading_count, 0)), 0) AS nominal_missing_reading_count,
            GREATEST((b.observed_expected_daily_reading_count - COALESCE(o.actual_reading_count, 0)), 0) AS observed_missing_reading_count,
            GREATEST((COALESCE(o.actual_reading_count, 0) - b.nominal_expected_daily_reading_count), 0) AS nominal_extra_reading_count,
            GREATEST((COALESCE(o.actual_reading_count, 0) - b.observed_expected_daily_reading_count), 0) AS observed_extra_reading_count,
            COALESCE(lg.large_gap_count, 0) AS large_gap_count,
            o.maximum_within_day_gap_seconds,
            o.first_timestamp_ms,
            o.last_timestamp_ms,
            (((COALESCE(o.actual_reading_count, 0))::numeric / (NULLIF(b.nominal_expected_daily_reading_count, 0))::numeric) * (100)::numeric) AS nominal_raw_completeness_percent,
            (((COALESCE(o.actual_reading_count, 0))::numeric / (NULLIF(b.observed_expected_daily_reading_count, 0))::numeric) * (100)::numeric) AS observed_raw_completeness_percent
           FROM (((device_calendar c
             JOIN silver.dq_device_cadence_staging b ON ((b.energy_meter_key = c.energy_meter_key)))
             LEFT JOIN daily_observed o ON (((o.device_id = c.energy_meter_key) AND (o.reading_date = c.reading_date))))
             LEFT JOIN daily_large_gaps lg ON (((lg.device_id = c.energy_meter_key) AND (lg.reading_date = c.reading_date))))
        ), classified AS (
         SELECT q.energy_meter_key,
            q.source_energy_meter_id,
            q.facility_key,
            q.zone_key,
            q.zone_name,
            q.device_name,
            q.meter_label,
            q.gateway_id,
            q.cadence_status,
            q.nominal_cadence_status,
            q.reading_date,
            q.nominal_gap_seconds,
            q.nominal_gap_minutes,
            q.nominal_expected_daily_reading_count,
            q.observed_gap_seconds,
            q.observed_gap_minutes,
            q.observed_expected_daily_reading_count,
            q.actual_reading_count,
            q.nominal_missing_reading_count,
            q.observed_missing_reading_count,
            q.nominal_extra_reading_count,
            q.observed_extra_reading_count,
            q.large_gap_count,
            q.maximum_within_day_gap_seconds,
            q.first_timestamp_ms,
            q.last_timestamp_ms,
            q.nominal_raw_completeness_percent,
            q.observed_raw_completeness_percent,
            (
                CASE
                    WHEN (q.actual_reading_count = 0) THEN 'CRITICAL_NO_DATA'::text
                    WHEN (q.actual_reading_count >= q.observed_expected_daily_reading_count) THEN 'COMPLETE_TO_OBSERVED_BASELINE'::text
                    WHEN ((q.observed_missing_reading_count <= 1) AND (q.large_gap_count = 0)) THEN 'COMPLETE_WITH_DAY_BOUNDARY_VARIATION'::text
                    WHEN (q.observed_raw_completeness_percent >= (95)::numeric) THEN 'WARNING_MINOR_MISSING_INTERVALS'::text
                    WHEN (q.observed_raw_completeness_percent >= (80)::numeric) THEN 'LOW_COMPLETENESS_REVIEW'::text
                    ELSE 'CRITICAL_INCOMPLETE_DAY'::text
                END COLLATE "C") AS observed_daily_quality_status,
            (
                CASE
                    WHEN (q.actual_reading_count = 0) THEN 'CRITICAL_NO_DATA'::text
                    WHEN ((q.nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text) AND (q.observed_raw_completeness_percent >= (99)::numeric) AND (q.large_gap_count = 0)) THEN 'BELOW_288_DUE_TO_STABLE_NONSTANDARD_CADENCE'::text
                    WHEN (q.nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text) THEN 'NONSTANDARD_CADENCE_WITH_DATA_GAPS'::text
                    WHEN ((q.actual_reading_count >= q.nominal_expected_daily_reading_count) AND (q.large_gap_count = 0)) THEN 'MEETS_NOMINAL_288_COUNT'::text
                    WHEN ((q.actual_reading_count = (q.nominal_expected_daily_reading_count - 1)) AND (q.large_gap_count = 0)) THEN 'ONE_READING_BELOW_NOMINAL_BOUNDARY_VARIATION'::text
                    WHEN (q.nominal_raw_completeness_percent >= (95)::numeric) THEN 'BELOW_NOMINAL_COUNT_MINOR'::text
                    WHEN (q.nominal_raw_completeness_percent >= (80)::numeric) THEN 'BELOW_NOMINAL_COUNT_REVIEW'::text
                    ELSE 'CRITICAL_BELOW_NOMINAL_COUNT'::text
                END COLLATE "C") AS nominal_reporting_status
           FROM quality_base q
        )
 SELECT energy_meter_key,
    source_energy_meter_id,
    facility_key,
    zone_key,
    zone_name,
    device_name,
    meter_label,
    gateway_id,
    reading_date,
    nominal_gap_seconds,
    nominal_gap_minutes,
    nominal_expected_daily_reading_count,
    observed_gap_seconds,
    observed_gap_minutes,
    observed_expected_daily_reading_count,
    observed_gap_seconds AS expected_gap_seconds,
    observed_gap_minutes AS expected_gap_minutes,
    observed_expected_daily_reading_count AS expected_daily_reading_count,
    actual_reading_count,
    nominal_missing_reading_count,
    observed_missing_reading_count,
    observed_missing_reading_count AS missing_reading_count,
    nominal_extra_reading_count,
    observed_extra_reading_count,
    round(nominal_raw_completeness_percent, 2) AS nominal_raw_completeness_percent,
    round(LEAST(nominal_raw_completeness_percent, (100)::numeric), 2) AS nominal_completeness_percent,
    round(observed_raw_completeness_percent, 2) AS observed_raw_completeness_percent,
    round(LEAST(observed_raw_completeness_percent, (100)::numeric), 2) AS observed_completeness_percent,
    round(observed_raw_completeness_percent, 2) AS raw_completeness_percent,
    round(LEAST(observed_raw_completeness_percent, (100)::numeric), 2) AS completeness_percent,
    large_gap_count,
    round(maximum_within_day_gap_seconds, 3) AS maximum_within_day_gap_seconds,
        CASE
            WHEN (first_timestamp_ms IS NULL) THEN NULL::timestamp without time zone
            ELSE (to_timestamp((((first_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text)
        END AS first_reading_utc,
        CASE
            WHEN (last_timestamp_ms IS NULL) THEN NULL::timestamp without time zone
            ELSE (to_timestamp((((last_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text)
        END AS last_reading_utc,
    cadence_status,
    nominal_cadence_status,
    observed_daily_quality_status,
    observed_daily_quality_status AS daily_quality_status,
    nominal_reporting_status,
    (
        CASE
            WHEN ((actual_reading_count = 0) OR (observed_raw_completeness_percent < (80)::numeric)) THEN 'CRITICAL'::text
            WHEN (observed_raw_completeness_percent < (95)::numeric) THEN 'ERROR'::text
            WHEN ((observed_raw_completeness_percent < (99)::numeric) OR (large_gap_count > 0)) THEN 'WARNING'::text
            ELSE 'INFO'::text
        END COLLATE "C") AS severity,
    (
        CASE
            WHEN ((actual_reading_count = 0) OR (observed_raw_completeness_percent < (80)::numeric)) THEN 'CRITICAL'::text
            WHEN (observed_raw_completeness_percent < (95)::numeric) THEN 'ERROR'::text
            WHEN (nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text) THEN 'WARNING'::text
            WHEN (nominal_raw_completeness_percent < (95)::numeric) THEN 'ERROR'::text
            WHEN ((nominal_raw_completeness_percent < (99)::numeric) OR (large_gap_count > 0)) THEN 'WARNING'::text
            ELSE 'INFO'::text
        END COLLATE "C") AS nominal_reporting_severity,
        CASE
            WHEN ((actual_reading_count = 0) OR (observed_raw_completeness_percent < (80)::numeric)) THEN false
            ELSE true
        END AS usable_for_daily_dashboard,
        CASE
            WHEN ((observed_raw_completeness_percent >= (99)::numeric) AND (large_gap_count = 0)) THEN true
            ELSE false
        END AS usable_for_ml_training,
        CASE
            WHEN (nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text) THEN true
            ELSE false
        END AS requires_cadence_normalization_for_ml,
        CASE
            WHEN (actual_reading_count >= nominal_expected_daily_reading_count) THEN true
            ELSE false
        END AS nominal_daily_count_met
   FROM classified
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW dq_meter_daily_completeness_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON MATERIALIZED VIEW silver.dq_meter_daily_completeness_staging IS 'One row per canonical meter per UTC day. Separates nominal 288-reading compliance from completeness relative to each meter''s observed cadence. Source telemetry is unchanged.';


--
-- Name: COLUMN dq_meter_daily_completeness_staging.nominal_expected_daily_reading_count; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_meter_daily_completeness_staging.nominal_expected_daily_reading_count IS 'Official target of 288 readings for a complete five-minute UTC day.';


--
-- Name: COLUMN dq_meter_daily_completeness_staging.observed_expected_daily_reading_count; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_meter_daily_completeness_staging.observed_expected_daily_reading_count IS 'Expected daily count calculated from each device''s observed historical median cadence.';


--
-- Name: COLUMN dq_meter_daily_completeness_staging.daily_quality_status; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_meter_daily_completeness_staging.daily_quality_status IS 'Backward-compatible observed-cadence data-quality status.';


--
-- Name: COLUMN dq_meter_daily_completeness_staging.nominal_reporting_status; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_meter_daily_completeness_staging.nominal_reporting_status IS 'Separate status showing compliance with the nominal five-minute/288-reading expectation.';


--
-- Name: dq_missing_intervals_staging; Type: MATERIALIZED VIEW; Schema: silver; Owner: -
--

CREATE MATERIALIZED VIEW silver.dq_missing_intervals_staging AS
 WITH ordered_readings AS (
         SELECT t.device_id,
            t."timestamp",
            lag(t."timestamp") OVER (PARTITION BY t.device_id ORDER BY t."timestamp") AS previous_timestamp
           FROM ((bronze.telemetries t
             JOIN bronze.telemetries_dictionaries td ON (((td.id = t.key_id) AND ((td.key)::text = 'TkW'::text))))
             JOIN silver.dq_device_cadence_staging b_1 ON (((b_1.energy_meter_key = t.device_id) AND b_1.cadence_baseline_is_reliable)))
        ), detected_gaps AS (
         SELECT r.device_id,
            r.previous_timestamp,
            r."timestamp",
            (((r."timestamp" - r.previous_timestamp))::numeric / 1000.0) AS actual_gap_seconds,
            b_1.nominal_gap_seconds,
            b_1.observed_gap_seconds,
            GREATEST(((round(((((r."timestamp" - r.previous_timestamp))::numeric / 1000.0) / b_1.observed_gap_seconds)))::integer - 1), 1) AS estimated_missing_readings_observed_cadence,
            GREATEST(((round(((((r."timestamp" - r.previous_timestamp))::numeric / 1000.0) / b_1.nominal_gap_seconds)))::integer - 1), 1) AS estimated_missing_readings_nominal_5min
           FROM (ordered_readings r
             JOIN silver.dq_device_cadence_staging b_1 ON ((b_1.energy_meter_key = r.device_id)))
          WHERE ((r.previous_timestamp IS NOT NULL) AND ((((r."timestamp" - r.previous_timestamp))::numeric / 1000.0) > (b_1.observed_gap_seconds * 1.5)))
        )
 SELECT b.energy_meter_key,
    b.source_energy_meter_id,
    b.facility_key,
    b.zone_key,
    b.zone_name,
    b.device_name,
    b.meter_label,
    b.gateway_id,
    (to_timestamp((((g.previous_timestamp)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text) AS previous_reading_utc,
    (to_timestamp((((g."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text) AS next_reading_utc,
    ((to_timestamp((((g.previous_timestamp)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date AS gap_start_date,
    ((to_timestamp((((g."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date AS gap_end_date,
    round(g.nominal_gap_seconds, 3) AS nominal_gap_seconds,
    round(g.observed_gap_seconds, 3) AS observed_gap_seconds,
    round(g.observed_gap_seconds, 3) AS expected_gap_seconds,
    round(g.actual_gap_seconds, 3) AS actual_gap_seconds,
    round((g.actual_gap_seconds / 60.0), 3) AS actual_gap_minutes,
    g.estimated_missing_readings_observed_cadence,
    g.estimated_missing_readings_nominal_5min,
    g.estimated_missing_readings_observed_cadence AS estimated_missing_readings,
    (
        CASE
            WHEN (g.estimated_missing_readings_observed_cadence >= 144) THEN 'CRITICAL'::text
            WHEN (g.estimated_missing_readings_observed_cadence >= 12) THEN 'ERROR'::text
            ELSE 'WARNING'::text
        END COLLATE "C") AS severity,
    (
        CASE
            WHEN (g.estimated_missing_readings_observed_cadence >= 144) THEN 'EXTENDED_DEVICE_OR_GATEWAY_OUTAGE'::text
            WHEN (g.estimated_missing_readings_observed_cadence >= 12) THEN 'LONG_MISSING_TELEMETRY_PERIOD'::text
            ELSE 'MISSING_TELEMETRY_INTERVAL'::text
        END COLLATE "C") AS issue_code
   FROM (detected_gaps g
     JOIN silver.dq_device_cadence_staging b ON ((b.energy_meter_key = g.device_id)))
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW dq_missing_intervals_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON MATERIALIZED VIEW silver.dq_missing_intervals_staging IS 'One row per detected TkW gap. Gap detection uses observed device cadence; nominal five-minute comparison is also retained. No missing values are inserted.';


--
-- Name: energy_meter_phase_map_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_meter_phase_map_landing AS
 SELECT parent_device,
    phase_parent,
    child_device,
    phase_child
   FROM bronze.energy_meter_phase_map;


--
-- Name: VIEW energy_meter_phase_map_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.energy_meter_phase_map_landing IS 'Landing view for bronze.energy_meter_phase_map. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: energy_saving_recommendations_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_saving_recommendations_landing AS
 SELECT id,
    facility_id,
    ((title)::text COLLATE "C") AS title,
    ((top_right_text)::text COLLATE "C") AS top_right_text,
    (body_text COLLATE "C") AS body_text,
    ((bottom_right_text)::text COLLATE "C") AS bottom_right_text,
    ((color)::text COLLATE "C") AS color,
    ((icon_class)::text COLLATE "C") AS icon_class,
    created_on
   FROM bronze.energy_saving_recommendations;


--
-- Name: VIEW energy_saving_recommendations_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.energy_saving_recommendations_landing IS 'Landing view for bronze.energy_saving_recommendations. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: telemetries_dictionaries_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.telemetries_dictionaries_landing AS
 SELECT id,
    ((key)::text COLLATE "C") AS key,
    created_on
   FROM bronze.telemetries_dictionaries;


--
-- Name: VIEW telemetries_dictionaries_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.telemetries_dictionaries_landing IS 'Landing view for bronze.telemetries_dictionaries. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: telemetries_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.telemetries_landing AS
 SELECT t.device_id,
    t.key_id,
    t."timestamp",
    t.bool,
        CASE
            WHEN (t.dbl IS NULL) THEN NULL::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['V1'::character varying, 'V2'::character varying, 'V3'::character varying, 'Vn1'::character varying, 'Vn2'::character varying, 'Vn3'::character varying, 'Va'::character varying, 'Vna'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['Amp1'::character varying, 'Amp2'::character varying, 'Amp3'::character varying, 'Ampa'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = 'Hz'::text) THEN (round((t.dbl)::numeric, 2))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['PF1'::character varying, 'PF2'::character varying, 'PF3'::character varying, 'PFa'::character varying])::text[])) THEN (round((t.dbl)::numeric, 2))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kW1'::character varying, 'kW2'::character varying, 'kW3'::character varying, 'TkW'::character varying])::text[])) THEN (round((t.dbl)::numeric, 3))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kVAr1'::character varying, 'kVAr2'::character varying, 'kVAr3'::character varying, 'TkVAr'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kWh'::character varying, 'kVArh'::character varying, 'kVAh'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kVA1'::character varying, 'kVA2'::character varying, 'kVA3'::character varying, 'TkVA'::character varying])::text[])) THEN (round((t.dbl)::numeric, 3))::double precision
            ELSE (round((t.dbl)::numeric, 9))::double precision
        END AS dbl,
    (t."json")::jsonb AS "json",
    t.long,
    ((t.str)::text COLLATE "C") AS str,
    (to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text) AS reading_timestamp_utc,
    (to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text) AS reading_timestamp_saudi,
    ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::date AS reading_date_saudi,
    ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::time without time zone AS reading_time_saudi,
    (to_char((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'YYYYMMDD'::text))::integer AS saudi_date_key,
    (to_char((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'HH24MISS'::text))::integer AS saudi_time_key
   FROM (bronze.telemetries t
     LEFT JOIN bronze.telemetries_dictionaries td ON ((td.id = t.key_id)));


--
-- Name: VIEW telemetries_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.telemetries_landing IS 'Landing view for bronze.telemetries. Preserves source rows and identifiers while applying measurement-key-specific floating-point presentation precision. Bronze remains exact.';


--
-- Name: fact_energy_readings_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.fact_energy_readings_staging AS
 WITH electrical_source AS (
         SELECT meter.energy_meter_key,
            meter.source_energy_meter_id,
            meter.facility_key,
            meter.zone_key,
            meter.grid_billing_account_key,
            t."timestamp" AS source_timestamp_ms,
            (to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text) AS reading_timestamp_utc,
            td.key AS telemetry_key,
            COALESCE(t.dbl, (t.long)::double precision) AS numeric_reading_value
           FROM ((silver.telemetries_landing t
             JOIN silver.dim_energy_meter_staging meter ON ((meter.energy_meter_key = t.device_id)))
             JOIN silver.telemetries_dictionaries_landing td ON ((td.id = t.key_id)))
          WHERE (td.key = ANY (ARRAY['V1'::text, 'V2'::text, 'V3'::text, 'Va'::text, 'Vn1'::text, 'Vn2'::text, 'Vn3'::text, 'Vna'::text, 'Amp1'::text, 'Amp2'::text, 'Amp3'::text, 'Ampa'::text, 'Hz'::text, 'PF1'::text, 'PF2'::text, 'PF3'::text, 'PFa'::text, 'kW1'::text, 'kW2'::text, 'kW3'::text, 'TkW'::text, 'kVA1'::text, 'kVA2'::text, 'kVA3'::text, 'TkVA'::text, 'kVAr1'::text, 'kVAr2'::text, 'kVAr3'::text, 'TkVAr'::text, 'kWh'::text, 'kVAh'::text, 'kVArh'::text]))
        ), pivoted AS (
         SELECT electrical_source.energy_meter_key,
            electrical_source.source_energy_meter_id,
            electrical_source.facility_key,
            electrical_source.zone_key,
            electrical_source.grid_billing_account_key,
            (to_char(((electrical_source.reading_timestamp_utc)::date)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS date_key,
            (to_char(electrical_source.reading_timestamp_utc, 'HH24MISS'::text))::integer AS time_key,
            electrical_source.source_timestamp_ms,
            electrical_source.reading_timestamp_utc,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'V1'::text)) AS voltage_line_1_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'V2'::text)) AS voltage_line_2_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'V3'::text)) AS voltage_line_3_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Va'::text)) AS voltage_line_average_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Vn1'::text)) AS voltage_neutral_1_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Vn2'::text)) AS voltage_neutral_2_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Vn3'::text)) AS voltage_neutral_3_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Vna'::text)) AS voltage_neutral_average_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Amp1'::text)) AS current_phase_1_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Amp2'::text)) AS current_phase_2_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Amp3'::text)) AS current_phase_3_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Ampa'::text)) AS current_average_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Hz'::text)) AS frequency_hz,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'PF1'::text)) AS power_factor_phase_1,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'PF2'::text)) AS power_factor_phase_2,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'PF3'::text)) AS power_factor_phase_3,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'PFa'::text)) AS power_factor_average,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kW1'::text)) AS active_power_phase_1_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kW2'::text)) AS active_power_phase_2_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kW3'::text)) AS active_power_phase_3_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'TkW'::text)) AS active_power_total_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVA1'::text)) AS apparent_power_phase_1_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVA2'::text)) AS apparent_power_phase_2_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVA3'::text)) AS apparent_power_phase_3_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'TkVA'::text)) AS apparent_power_total_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVAr1'::text)) AS reactive_power_phase_1_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVAr2'::text)) AS reactive_power_phase_2_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVAr3'::text)) AS reactive_power_phase_3_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'TkVAr'::text)) AS reactive_power_total_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kWh'::text)) AS active_energy_cumulative_kwh,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVAh'::text)) AS apparent_energy_cumulative_kvah,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVArh'::text)) AS reactive_energy_cumulative_kvarh,
            (count(*))::integer AS source_measurement_row_count,
            (count(DISTINCT electrical_source.telemetry_key))::integer AS populated_measurement_count,
            ((count(*) - count(DISTINCT electrical_source.telemetry_key)))::integer AS duplicate_measurement_row_count,
            (to_timestamp((((electrical_source.source_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text) AS reading_timestamp_saudi,
            ((to_timestamp((((electrical_source.source_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::date AS reading_date_saudi,
            ((to_timestamp((((electrical_source.source_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::time without time zone AS reading_time_saudi,
            (to_char((to_timestamp((((electrical_source.source_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'YYYYMMDD'::text))::integer AS saudi_date_key,
            (to_char((to_timestamp((((electrical_source.source_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'HH24MISS'::text))::integer AS saudi_time_key
           FROM electrical_source
          GROUP BY electrical_source.energy_meter_key, electrical_source.source_energy_meter_id, electrical_source.facility_key, electrical_source.zone_key, electrical_source.grid_billing_account_key, electrical_source.source_timestamp_ms, electrical_source.reading_timestamp_utc
        )
 SELECT p.energy_meter_key,
    p.source_energy_meter_id,
    p.facility_key,
    p.zone_key,
    p.grid_billing_account_key,
    p.date_key,
    p.time_key,
    p.source_timestamp_ms,
    p.reading_timestamp_utc,
    p.voltage_line_1_v,
    p.voltage_line_2_v,
    p.voltage_line_3_v,
    p.voltage_line_average_v,
    p.voltage_neutral_1_v,
    p.voltage_neutral_2_v,
    p.voltage_neutral_3_v,
    p.voltage_neutral_average_v,
    p.current_phase_1_a,
    p.current_phase_2_a,
    p.current_phase_3_a,
    p.current_average_a,
    p.frequency_hz,
    p.power_factor_phase_1,
    p.power_factor_phase_2,
    p.power_factor_phase_3,
    p.power_factor_average,
    p.active_power_phase_1_kw,
    p.active_power_phase_2_kw,
    p.active_power_phase_3_kw,
    p.active_power_total_kw,
    p.apparent_power_phase_1_kva,
    p.apparent_power_phase_2_kva,
    p.apparent_power_phase_3_kva,
    p.apparent_power_total_kva,
    p.reactive_power_phase_1_kvar,
    p.reactive_power_phase_2_kvar,
    p.reactive_power_phase_3_kvar,
    p.reactive_power_total_kvar,
    p.active_energy_cumulative_kwh,
    p.apparent_energy_cumulative_kvah,
    p.reactive_energy_cumulative_kvarh,
    p.source_measurement_row_count,
    p.populated_measurement_count,
    p.duplicate_measurement_row_count,
    p.reading_timestamp_saudi,
    p.reading_date_saudi,
    p.reading_time_saudi,
    p.saudi_date_key,
    p.saudi_time_key,
        CASE
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) = 3)) THEN (round(((((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS calculated_current_average_a,
        CASE
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) = 3)) THEN (round(((GREATEST(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) - LEAST(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a)))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS current_phase_spread_a,
        CASE
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) = 3) AND (abs((((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision)) > (0.1)::double precision)) THEN (round(((((100.0)::double precision * GREATEST(abs((p.current_phase_1_a - (((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision))), abs((p.current_phase_2_a - (((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision))), abs((p.current_phase_3_a - (((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision))))) / abs((((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision))))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS current_imbalance_pct,
    (
        CASE
            WHEN (m.phase_count IS NULL) THEN 'PHASE_COUNT_UNKNOWN'::text
            WHEN (m.phase_count <> 3) THEN 'NOT_APPLICABLE_NON_THREE_PHASE'::text
            WHEN (num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) < 3) THEN 'INSUFFICIENT_PHASE_DATA'::text
            WHEN (abs((((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision)) <= (0.1)::double precision) THEN 'LOW_LOAD_NOT_EVALUATED'::text
            ELSE 'EVALUATED'::text
        END COLLATE "C") AS current_imbalance_evaluation_status,
        CASE
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) = 3)) THEN (round(((((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS calculated_voltage_average_v,
        CASE
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) = 3)) THEN (round(((GREATEST(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) - LEAST(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v)))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS voltage_phase_spread_v,
        CASE
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) = 3) AND (abs((((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision)) > (1.0)::double precision)) THEN (round(((((100.0)::double precision * GREATEST(abs((p.voltage_line_1_v - (((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision))), abs((p.voltage_line_2_v - (((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision))), abs((p.voltage_line_3_v - (((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision))))) / abs((((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision))))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS voltage_imbalance_pct,
    (
        CASE
            WHEN (m.phase_count IS NULL) THEN 'PHASE_COUNT_UNKNOWN'::text
            WHEN (m.phase_count <> 3) THEN 'NOT_APPLICABLE_NON_THREE_PHASE'::text
            WHEN (num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) < 3) THEN 'INSUFFICIENT_PHASE_DATA'::text
            WHEN (abs((((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision)) <= (1.0)::double precision) THEN 'LOW_VOLTAGE_NOT_EVALUATED'::text
            ELSE 'EVALUATED'::text
        END COLLATE "C") AS voltage_imbalance_evaluation_status
   FROM (pivoted p
     LEFT JOIN silver.dim_energy_meter_staging m ON ((m.energy_meter_key = p.energy_meter_key)));


--
-- Name: VIEW fact_energy_readings_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.fact_energy_readings_staging IS 'Main project fact. One energy meter per telemetry timestamp with electrical measures pivoted into business-readable columns.';


--
-- Name: fact_energy_readings_flagged; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.fact_energy_readings_flagged AS
 WITH base AS (
         SELECT f.energy_meter_key,
            f.source_energy_meter_id,
            f.facility_key,
            f.zone_key,
            f.grid_billing_account_key,
            f.date_key,
            f.time_key,
            f.source_timestamp_ms,
            f.reading_timestamp_utc,
            f.reading_timestamp_saudi,
            f.reading_date_saudi,
            f.voltage_line_1_v,
            f.voltage_line_2_v,
            f.voltage_line_3_v,
            f.voltage_line_average_v,
            f.voltage_neutral_1_v,
            f.voltage_neutral_2_v,
            f.voltage_neutral_3_v,
            f.voltage_neutral_average_v,
            f.current_phase_1_a,
            f.current_phase_2_a,
            f.current_phase_3_a,
            f.active_power_phase_1_kw,
            f.active_power_phase_2_kw,
            f.active_power_phase_3_kw,
            f.frequency_hz,
            f.power_factor_phase_1,
            f.power_factor_phase_2,
            f.power_factor_phase_3,
            f.power_factor_average,
            f.active_energy_cumulative_kwh,
            cb.cb_max_rating_a,
            lag(f.active_energy_cumulative_kwh) OVER w AS prev_kwh
           FROM (silver.fact_energy_readings_staging f
             LEFT JOIN silver.dim_meter_cb_rating cb ON ((cb.energy_meter_key = f.energy_meter_key)))
          WINDOW w AS (PARTITION BY f.energy_meter_key ORDER BY f.reading_timestamp_utc)
        ), statuses AS (
         SELECT b.energy_meter_key,
            b.source_energy_meter_id,
            b.facility_key,
            b.zone_key,
            b.grid_billing_account_key,
            b.date_key,
            b.time_key,
            b.source_timestamp_ms,
            b.reading_timestamp_utc,
            b.reading_timestamp_saudi,
            b.reading_date_saudi,
            silver.classify_voltage_neutral_v2(b.voltage_neutral_1_v) AS status_vn1,
            silver.classify_voltage_neutral_v2(b.voltage_neutral_2_v) AS status_vn2,
            silver.classify_voltage_neutral_v2(b.voltage_neutral_3_v) AS status_vn3,
            silver.classify_voltage_line_v2(b.voltage_line_1_v) AS status_v1,
            silver.classify_voltage_line_v2(b.voltage_line_2_v) AS status_v2,
            silver.classify_voltage_line_v2(b.voltage_line_3_v) AS status_v3,
            silver.classify_current_v2(b.current_phase_1_a, b.cb_max_rating_a, b.active_power_phase_1_kw) AS status_amp1,
            silver.classify_current_v2(b.current_phase_2_a, b.cb_max_rating_a, b.active_power_phase_2_kw) AS status_amp2,
            silver.classify_current_v2(b.current_phase_3_a, b.cb_max_rating_a, b.active_power_phase_3_kw) AS status_amp3,
            silver.classify_frequency_v2(b.frequency_hz) AS status_hz,
            silver.classify_power_factor_v2(b.power_factor_phase_1) AS status_pf1,
            silver.classify_power_factor_v2(b.power_factor_phase_2) AS status_pf2,
            silver.classify_power_factor_v2(b.power_factor_phase_3) AS status_pf3,
            silver.classify_power_factor_v2(b.power_factor_average) AS status_pfa,
            silver.classify_accumulated_energy_v2(b.active_energy_cumulative_kwh, b.prev_kwh) AS status_kwh
           FROM base b
        )
 SELECT energy_meter_key,
    source_energy_meter_id,
    facility_key,
    zone_key,
    grid_billing_account_key,
    date_key,
    time_key,
    source_timestamp_ms,
    reading_timestamp_utc,
    reading_timestamp_saudi,
    reading_date_saudi,
    status_vn1,
    status_vn2,
    status_vn3,
    status_v1,
    status_v2,
    status_v3,
    status_amp1,
    status_amp2,
    status_amp3,
    status_hz,
    status_pf1,
    status_pf2,
    status_pf3,
    status_pfa,
    status_kwh,
    silver.worst_status(VARIADIC ARRAY[status_vn1, status_vn2, status_vn3, status_v1, status_v2, status_v3, status_hz, status_pf1, status_pf2, status_pf3, status_pfa, status_kwh]) AS overall_status
   FROM statuses;


--
-- Name: firmwares_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.firmwares_landing AS
 SELECT id,
    ((filename)::text COLLATE "C") AS filename,
    ((client_id)::text COLLATE "C") AS client_id,
    ((version)::text COLLATE "C") AS version,
    created_by,
    created_on
   FROM bronze.firmwares;


--
-- Name: VIEW firmwares_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.firmwares_landing IS 'Landing view for bronze.firmwares. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: floor_plan_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.floor_plan_landing AS
 SELECT id,
    unit_id,
    ((name)::text COLLATE "C") AS name,
    image_proprties,
    created_by,
    created_on
   FROM bronze.floor_plan;


--
-- Name: VIEW floor_plan_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.floor_plan_landing IS 'Landing view for bronze.floor_plan. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: forget_password_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.forget_password_landing AS
 SELECT id,
    user_id,
    active,
    created_on,
    expires_on,
    ((token)::text COLLATE "C") AS token
   FROM bronze.forget_password;


--
-- Name: VIEW forget_password_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.forget_password_landing IS 'Landing view for bronze.forget_password. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: icons_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.icons_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((css_class)::text COLLATE "C") AS css_class,
    active,
    created_on
   FROM bronze.icons;


--
-- Name: VIEW icons_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.icons_landing IS 'Landing view for bronze.icons. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: label_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.label_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    (description COLLATE "C") AS description,
    created_on,
    created_by
   FROM bronze.label_types;


--
-- Name: VIEW label_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.label_types_landing IS 'Landing view for bronze.label_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: labels_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.labels_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((icon)::text COLLATE "C") AS icon,
    (description COLLATE "C") AS description,
    ((hex_color)::text COLLATE "C") AS hex_color,
    active,
    label_type_id,
    created_on,
    created_by
   FROM bronze.labels;


--
-- Name: VIEW labels_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.labels_landing IS 'Landing view for bronze.labels. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: migratehistory_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.migratehistory_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    migrated_at
   FROM bronze.migratehistory;


--
-- Name: VIEW migratehistory_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.migratehistory_landing IS 'Landing view for bronze.migratehistory. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: modules_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.modules_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title,
    ((html_class)::text COLLATE "C") AS html_class,
    ((color)::text COLLATE "C") AS color,
    has_children,
    level,
    parent_id,
    priority,
    ((route_to)::text COLLATE "C") AS route_to,
    created_on
   FROM bronze.modules;


--
-- Name: VIEW modules_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.modules_landing IS 'Landing view for bronze.modules. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: mqtt_service_accounts_allowed_topics_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.mqtt_service_accounts_allowed_topics_landing AS
 SELECT id,
    mqtt_topic_id,
    access,
    active,
    mqtt_service_account_id,
    created_on,
    created_by
   FROM bronze.mqtt_service_accounts_allowed_topics;


--
-- Name: VIEW mqtt_service_accounts_allowed_topics_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.mqtt_service_accounts_allowed_topics_landing IS 'Landing view for bronze.mqtt_service_accounts_allowed_topics. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: mqtt_service_accounts_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.mqtt_service_accounts_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((username)::text COLLATE "C") AS username,
    ((password)::text COLLATE "C") AS password,
    (description COLLATE "C") AS description,
    active,
    facility_id,
    created_on,
    created_by
   FROM bronze.mqtt_service_accounts;


--
-- Name: VIEW mqtt_service_accounts_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.mqtt_service_accounts_landing IS 'Landing view for bronze.mqtt_service_accounts. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: mqtt_topics_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.mqtt_topics_landing AS
 SELECT id,
    ((topic)::text COLLATE "C") AS topic,
    ((regex)::text COLLATE "C") AS regex,
    active,
    created_on,
    facility_id
   FROM bronze.mqtt_topics;


--
-- Name: VIEW mqtt_topics_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.mqtt_topics_landing IS 'Landing view for bronze.mqtt_topics. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: multi_factor_authentication_factors_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.multi_factor_authentication_factors_landing AS
 SELECT id,
    ((token)::text COLLATE "C") AS token,
    (additional_config)::jsonb AS additional_config,
    type_id,
    active
   FROM bronze.multi_factor_authentication_factors;


--
-- Name: VIEW multi_factor_authentication_factors_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.multi_factor_authentication_factors_landing IS 'Landing view for bronze.multi_factor_authentication_factors. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: multi_factor_authentication_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.multi_factor_authentication_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    created_on
   FROM bronze.multi_factor_authentication_types;


--
-- Name: VIEW multi_factor_authentication_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.multi_factor_authentication_types_landing IS 'Landing view for bronze.multi_factor_authentication_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: notification_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.notification_types_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title
   FROM bronze.notification_types;


--
-- Name: VIEW notification_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.notification_types_landing IS 'Landing view for bronze.notification_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: notifications_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.notifications_landing AS
 SELECT id,
    notification_group_id,
    contact_id,
    contact_method_id,
    notification_type_id,
    successfully_sent,
    read,
    read_ts,
    "timestamp",
    (details)::jsonb AS details
   FROM bronze.notifications;


--
-- Name: VIEW notifications_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.notifications_landing IS 'Landing view for bronze.notifications. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: overlay_controllers_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.overlay_controllers_landing AS
 SELECT overlay_id,
    controller_id
   FROM bronze.overlay_controllers;


--
-- Name: VIEW overlay_controllers_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.overlay_controllers_landing IS 'Landing view for bronze.overlay_controllers. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: overlays_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.overlays_landing AS
 SELECT id,
    unit_id,
    floor_plan_id,
    ((name)::text COLLATE "C") AS name,
    shape_config,
    created_by,
    created_on
   FROM bronze.overlays;


--
-- Name: VIEW overlays_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.overlays_landing IS 'Landing view for bronze.overlays. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: permissions_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.permissions_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    read,
    "create",
    update,
    delete,
    control,
    billing,
    is_core,
    created_by,
    created_on
   FROM bronze.permissions;


--
-- Name: VIEW permissions_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.permissions_landing IS 'Landing view for bronze.permissions. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: role_module_permission_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.role_module_permission_landing AS
 SELECT role_id,
    module_id,
    permission_id,
    created_on,
    created_by
   FROM bronze.role_module_permission;


--
-- Name: VIEW role_module_permission_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.role_module_permission_landing IS 'Landing view for bronze.role_module_permission. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: role_units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.role_units_landing AS
 SELECT role_id,
    unit_id,
    unit_level,
    created_on,
    created_by
   FROM bronze.role_units;


--
-- Name: VIEW role_units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.role_units_landing IS 'Landing view for bronze.role_units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: roles_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.roles_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    (description COLLATE "C") AS description,
    global_role,
    ((icon)::text COLLATE "C") AS icon,
    ((icon_color)::text COLLATE "C") AS icon_color,
    active,
    created_on,
    created_by,
    facility_id
   FROM bronze.roles;


--
-- Name: VIEW roles_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.roles_landing IS 'Landing view for bronze.roles. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: schedule_controllers_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.schedule_controllers_landing AS
 SELECT id,
    schedule_id,
    controller_id,
    execution_sequence,
    ((controller_action)::text COLLATE "C") AS controller_action,
    created_on,
    created_by
   FROM bronze.schedule_controllers;


--
-- Name: VIEW schedule_controllers_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.schedule_controllers_landing IS 'Landing view for bronze.schedule_controllers. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: schedule_jobs_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.schedule_jobs_landing AS
 SELECT ((job_id)::text COLLATE "C") AS job_id,
    schedule_id,
    created_on
   FROM bronze.schedule_jobs;


--
-- Name: VIEW schedule_jobs_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.schedule_jobs_landing IS 'Landing view for bronze.schedule_jobs. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: schedule_labels_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.schedule_labels_landing AS
 SELECT id,
    schedule_id,
    label_id,
    created_on,
    created_by
   FROM bronze.schedule_labels;


--
-- Name: VIEW schedule_labels_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.schedule_labels_landing IS 'Landing view for bronze.schedule_labels. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: schedule_units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.schedule_units_landing AS
 SELECT id,
    schedule_id,
    unit_id,
    created_on,
    created_by
   FROM bronze.schedule_units;


--
-- Name: VIEW schedule_units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.schedule_units_landing IS 'Landing view for bronze.schedule_units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: schedules_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.schedules_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    (description COLLATE "C") AS description,
    start_datetime,
    end_datetime,
    schedule_duration,
    triggers,
    active,
    created_on,
    created_by,
    ((schedule_type)::text COLLATE "C") AS schedule_type
   FROM bronze.schedules;


--
-- Name: VIEW schedules_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.schedules_landing IS 'Landing view for bronze.schedules. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: tariff_categories_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.tariff_categories_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    maximum_amp,
    minimum_amp,
    fee,
    active,
    facility_id,
    created_on,
    created_by
   FROM bronze.tariff_categories;


--
-- Name: VIEW tariff_categories_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.tariff_categories_landing IS 'Landing view for bronze.tariff_categories. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: telemetries_latest_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.telemetries_latest_landing AS
 SELECT t.device_id,
    t.key_id,
    t."timestamp",
    t.bool,
        CASE
            WHEN (t.dbl IS NULL) THEN NULL::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['V1'::character varying, 'V2'::character varying, 'V3'::character varying, 'Vn1'::character varying, 'Vn2'::character varying, 'Vn3'::character varying, 'Va'::character varying, 'Vna'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['Amp1'::character varying, 'Amp2'::character varying, 'Amp3'::character varying, 'Ampa'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = 'Hz'::text) THEN (round((t.dbl)::numeric, 2))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['PF1'::character varying, 'PF2'::character varying, 'PF3'::character varying, 'PFa'::character varying])::text[])) THEN (round((t.dbl)::numeric, 2))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kW1'::character varying, 'kW2'::character varying, 'kW3'::character varying, 'TkW'::character varying])::text[])) THEN (round((t.dbl)::numeric, 3))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kVAr1'::character varying, 'kVAr2'::character varying, 'kVAr3'::character varying, 'TkVAr'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kWh'::character varying, 'kVArh'::character varying, 'kVAh'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kVA1'::character varying, 'kVA2'::character varying, 'kVA3'::character varying, 'TkVA'::character varying])::text[])) THEN (round((t.dbl)::numeric, 3))::double precision
            ELSE (round((t.dbl)::numeric, 9))::double precision
        END AS dbl,
    (t."json")::jsonb AS "json",
    t.long,
    ((t.str)::text COLLATE "C") AS str,
    (to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text) AS reading_timestamp_utc,
    (to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text) AS reading_timestamp_saudi,
    ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::date AS reading_date_saudi,
    ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::time without time zone AS reading_time_saudi,
    (to_char((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'YYYYMMDD'::text))::integer AS saudi_date_key,
    (to_char((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'HH24MISS'::text))::integer AS saudi_time_key
   FROM (bronze.telemetries_latest t
     LEFT JOIN bronze.telemetries_dictionaries td ON ((td.id = t.key_id)));


--
-- Name: VIEW telemetries_latest_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.telemetries_latest_landing IS 'Landing view for bronze.telemetries_latest. Preserves source rows and identifiers while applying the same measurement-specific presentation precision as historical telemetry. Bronze remains exact.';


--
-- Name: telemetries_notif_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.telemetries_notif_landing AS
 SELECT id,
    device_id,
    key_id,
    "timestamp",
    bool,
        CASE
            WHEN (dbl IS NULL) THEN NULL::double precision
            ELSE (round((dbl)::numeric, 9))::double precision
        END AS dbl,
    ("json")::jsonb AS "json",
    long,
    ((str)::text COLLATE "C") AS str,
    ((msg)::text COLLATE "C") AS msg
   FROM bronze.telemetries_notif;


--
-- Name: VIEW telemetries_notif_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.telemetries_notif_landing IS 'Landing view for bronze.telemetries_notif. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: telemetries_notif_users_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.telemetries_notif_users_landing AS
 SELECT notif_id,
    user_id,
    read,
    read_ts
   FROM bronze.telemetries_notif_users;


--
-- Name: VIEW telemetries_notif_users_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.telemetries_notif_users_landing IS 'Landing view for bronze.telemetries_notif_users. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: upload_batch_items_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.upload_batch_items_landing AS
 SELECT id,
    batch_id,
    status_id,
    (original_filename COLLATE "C") AS original_filename,
    created_at,
    (details)::jsonb AS details
   FROM bronze.upload_batch_items;


--
-- Name: VIEW upload_batch_items_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.upload_batch_items_landing IS 'Landing view for bronze.upload_batch_items. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: upload_batches_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.upload_batches_landing AS
 SELECT id,
    type_id,
    created_by,
    created_at,
    user_notified,
    notified_at,
    (details)::jsonb AS details
   FROM bronze.upload_batches;


--
-- Name: VIEW upload_batches_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.upload_batches_landing IS 'Landing view for bronze.upload_batches. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: upload_batches_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.upload_batches_types_landing AS
 SELECT id,
    (name COLLATE "C") AS name
   FROM bronze.upload_batches_types;


--
-- Name: VIEW upload_batches_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.upload_batches_types_landing IS 'Landing view for bronze.upload_batches_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: upload_status_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.upload_status_landing AS
 SELECT id,
    (name COLLATE "C") AS name
   FROM bronze.upload_status;


--
-- Name: VIEW upload_status_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.upload_status_landing IS 'Landing view for bronze.upload_status. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: users_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.users_landing AS
 SELECT id,
    ((email)::text COLLATE "C") AS email,
    ((first_name)::text COLLATE "C") AS first_name,
    ((last_name)::text COLLATE "C") AS last_name,
    ((password)::text COLLATE "C") AS password,
    role_id,
    active,
    mfa_factor_id,
    created_on,
    facility_id,
    mqtt_account_id,
    ((avatar)::text COLLATE "C") AS avatar,
    (preferences)::jsonb AS preferences,
    address_id,
    force_mfa
   FROM bronze.users;


--
-- Name: VIEW users_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.users_landing IS 'Landing view for bronze.users. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_bill_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_bill_landing AS
 SELECT id,
    water_grid_account_id,
    ((water_grid_invoice_number)::text COLLATE "C") AS water_grid_invoice_number,
    grid_period_begin,
    grid_period_end,
        CASE
            WHEN (grid_begin_reading IS NULL) THEN NULL::real
            ELSE (round((grid_begin_reading)::numeric, 6))::real
        END AS grid_begin_reading,
        CASE
            WHEN (grid_end_reading IS NULL) THEN NULL::real
            ELSE (round((grid_end_reading)::numeric, 6))::real
        END AS grid_end_reading,
        CASE
            WHEN (grid_consumption IS NULL) THEN NULL::real
            ELSE (round((grid_consumption)::numeric, 6))::real
        END AS grid_consumption,
        CASE
            WHEN (grid_cost IS NULL) THEN NULL::real
            ELSE (round((grid_cost)::numeric, 6))::real
        END AS grid_cost,
        CASE
            WHEN (system_begin_reading IS NULL) THEN NULL::real
            ELSE (round((system_begin_reading)::numeric, 6))::real
        END AS system_begin_reading,
        CASE
            WHEN (system_end_reading IS NULL) THEN NULL::real
            ELSE (round((system_end_reading)::numeric, 6))::real
        END AS system_end_reading,
        CASE
            WHEN (system_consumption IS NULL) THEN NULL::real
            ELSE (round((system_consumption)::numeric, 6))::real
        END AS system_consumption,
        CASE
            WHEN (system_cost IS NULL) THEN NULL::real
            ELSE (round((system_cost)::numeric, 6))::real
        END AS system_cost,
    (cost_details)::jsonb AS cost_details,
        CASE
            WHEN (consumption_different IS NULL) THEN NULL::real
            ELSE (round((consumption_different)::numeric, 6))::real
        END AS consumption_different,
    created_on,
    created_by
   FROM bronze.water_bill;


--
-- Name: VIEW water_bill_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_bill_landing IS 'Landing view for bronze.water_bill. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_bill_water_meter_consume_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_bill_water_meter_consume_landing AS
 SELECT water_bill_id,
    water_meter_id,
        CASE
            WHEN (water_meter_consume IS NULL) THEN NULL::real
            ELSE (round((water_meter_consume)::numeric, 6))::real
        END AS water_meter_consume,
    created_on,
    created_by
   FROM bronze.water_bill_water_meter_consume;


--
-- Name: VIEW water_bill_water_meter_consume_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_bill_water_meter_consume_landing IS 'Landing view for bronze.water_bill_water_meter_consume. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_global_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_global_types_landing AS
 SELECT water_grid_account_id,
    global_type_id,
    created_on,
    created_by
   FROM bronze.water_grid_account_global_types;


--
-- Name: VIEW water_grid_account_global_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_global_types_landing IS 'Landing view for bronze.water_grid_account_global_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    account_number,
    ((meter_serial_number)::text COLLATE "C") AS meter_serial_number,
    water_grid_provider_id,
    service_type_id,
    service_class_id,
    start_period,
    end_period,
    account_cycle_days,
    is_new_tariff,
    grid_account_units_count,
    created_by,
    created_on
   FROM bronze.water_grid_account;


--
-- Name: VIEW water_grid_account_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_landing IS 'Landing view for bronze.water_grid_account. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_service_class_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_service_class_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    minimal_meter_diameter,
    maximum_meter_diameter,
    fee,
    active,
    water_grid_provider_id,
    created_on,
    created_by
   FROM bronze.water_grid_account_service_class;


--
-- Name: VIEW water_grid_account_service_class_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_service_class_landing IS 'Landing view for bronze.water_grid_account_service_class. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_service_global_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_service_global_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ratio_bill,
    water_grid_provider_id,
    active,
    created_on,
    created_by
   FROM bronze.water_grid_account_service_global;


--
-- Name: VIEW water_grid_account_service_global_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_service_global_landing IS 'Landing view for bronze.water_grid_account_service_global. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_service_sub_type_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_service_sub_type_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    first,
    second,
    third,
    fourth,
    above,
    active,
    created_on,
    created_by
   FROM bronze.water_grid_account_service_sub_type;


--
-- Name: VIEW water_grid_account_service_sub_type_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_service_sub_type_landing IS 'Landing view for bronze.water_grid_account_service_sub_type. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_service_type_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_service_type_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    c_base,
    s1,
    s2,
    s3,
    s4,
    s5,
    water_grid_provider_id,
    active,
    created_on,
    created_by
   FROM bronze.water_grid_account_service_type;


--
-- Name: VIEW water_grid_account_service_type_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_service_type_landing IS 'Landing view for bronze.water_grid_account_service_type. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_units_landing AS
 SELECT water_grid_account_id,
    unit_id,
    created_on,
    created_by
   FROM bronze.water_grid_account_units;


--
-- Name: VIEW water_grid_account_units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_units_landing IS 'Landing view for bronze.water_grid_account_units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_provider_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_provider_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    created_on,
    created_by
   FROM bronze.water_grid_provider;


--
-- Name: VIEW water_grid_provider_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_provider_landing IS 'Landing view for bronze.water_grid_provider. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_water_meters_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_water_meters_landing AS
 SELECT water_grid_account_id,
    water_meter_id,
    created_on,
    created_by,
    grid_account_main_meter
   FROM bronze.water_grid_water_meters;


--
-- Name: VIEW water_grid_water_meters_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_water_meters_landing IS 'Landing view for bronze.water_grid_water_meters. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_meter_units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_meter_units_landing AS
 SELECT water_meter_id,
    unit_id,
    created_on,
    created_by,
    unit_main_meter
   FROM bronze.water_meter_units;


--
-- Name: VIEW water_meter_units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_meter_units_landing IS 'Landing view for bronze.water_meter_units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_tank_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_tank_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    capacity,
    width,
    body_height,
    inside_water_height,
    length,
    diameter,
    thickness,
    max_temperature,
    min_temperature,
    max_pressure,
    min_pressure,
    water_source_id,
    type_id,
    location_id,
    active,
    created_by,
    created_on,
    label_id
   FROM bronze.water_tank;


--
-- Name: VIEW water_tank_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_tank_landing IS 'Landing view for bronze.water_tank. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_tank_type_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_tank_type_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    created_by,
    created_on
   FROM bronze.water_tank_type;


--
-- Name: VIEW water_tank_type_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_tank_type_landing IS 'Landing view for bronze.water_tank_type. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_tank_units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_tank_units_landing AS
 SELECT water_tank_id,
    unit_id,
    created_on,
    created_by
   FROM bronze.water_tank_units;


--
-- Name: VIEW water_tank_units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_tank_units_landing IS 'Landing view for bronze.water_tank_units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_tank_water_sensors_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_tank_water_sensors_landing AS
 SELECT water_tank_id,
    water_sensor_id,
    ((telemetry_key)::text COLLATE "C") AS telemetry_key,
    telemetry_key_id,
    control_id,
    ((category_name)::text COLLATE "C") AS category_name,
    created_on,
    created_by
   FROM bronze.water_tank_water_sensors;


--
-- Name: VIEW water_tank_water_sensors_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_tank_water_sensors_landing IS 'Landing view for bronze.water_tank_water_sensors. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


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
-- Name: agg_energy_1d agg_energy_1d_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_1d
    ADD CONSTRAINT agg_energy_1d_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_1h agg_energy_1h_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_1h
    ADD CONSTRAINT agg_energy_1h_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_1month agg_energy_1month_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_1month
    ADD CONSTRAINT agg_energy_1month_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_1week agg_energy_1week_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_1week
    ADD CONSTRAINT agg_energy_1week_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_30min agg_energy_30min_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_30min
    ADD CONSTRAINT agg_energy_30min_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_3d agg_energy_3d_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_3d
    ADD CONSTRAINT agg_energy_3d_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_4h agg_energy_4h_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_4h
    ADD CONSTRAINT agg_energy_4h_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: data_quality_summary data_quality_summary_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.data_quality_summary
    ADD CONSTRAINT data_quality_summary_pkey PRIMARY KEY (energy_meter_key);


--
-- Name: dim_meter_cb_rating dim_meter_cb_rating_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.dim_meter_cb_rating
    ADD CONSTRAINT dim_meter_cb_rating_pkey PRIMARY KEY (energy_meter_key);


--
-- Name: fact_energy_readings_snapshot pk_energy_readings_snapshot; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.fact_energy_readings_snapshot
    ADD CONSTRAINT pk_energy_readings_snapshot PRIMARY KEY (energy_meter_key, reading_timestamp_utc);


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
-- Name: idx_consumption_date; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX idx_consumption_date ON silver.fact_energy_consumption_validated USING btree (reading_date_saudi);


--
-- Name: idx_consumption_meter_label; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX idx_consumption_meter_label ON silver.fact_energy_consumption_validated USING btree (meter_label);


--
-- Name: idx_consumption_meter_time; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX idx_consumption_meter_time ON silver.fact_energy_consumption_validated USING btree (energy_meter_key, reading_timestamp_utc);


--
-- Name: ix_dq_daily_completeness_status; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_daily_completeness_status ON silver.dq_meter_daily_completeness_staging USING btree (daily_quality_status, severity);


--
-- Name: ix_dq_daily_completeness_zone_date; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_daily_completeness_zone_date ON silver.dq_meter_daily_completeness_staging USING btree (zone_key, reading_date);


--
-- Name: ix_dq_daily_nominal_reporting_status; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_daily_nominal_reporting_status ON silver.dq_meter_daily_completeness_staging USING btree (nominal_reporting_status, nominal_reporting_severity);


--
-- Name: ix_dq_device_cadence_status; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_device_cadence_status ON silver.dq_device_cadence_staging USING btree (cadence_status, nominal_cadence_status);


--
-- Name: ix_dq_device_cadence_zone; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_device_cadence_zone ON silver.dq_device_cadence_staging USING btree (zone_key, device_name);


--
-- Name: ix_dq_missing_intervals_meter_time; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_missing_intervals_meter_time ON silver.dq_missing_intervals_staging USING btree (energy_meter_key, previous_reading_utc);


--
-- Name: ix_dq_missing_intervals_severity; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_missing_intervals_severity ON silver.dq_missing_intervals_staging USING btree (severity);


--
-- Name: ix_dq_missing_intervals_zone_time; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_missing_intervals_zone_time ON silver.dq_missing_intervals_staging USING btree (zone_key, previous_reading_utc);


--
-- Name: ux_dq_daily_completeness_meter_date; Type: INDEX; Schema: silver; Owner: -
--

CREATE UNIQUE INDEX ux_dq_daily_completeness_meter_date ON silver.dq_meter_daily_completeness_staging USING btree (energy_meter_key, reading_date);


--
-- Name: ux_dq_device_cadence_energy_meter; Type: INDEX; Schema: silver; Owner: -
--

CREATE UNIQUE INDEX ux_dq_device_cadence_energy_meter ON silver.dq_device_cadence_staging USING btree (energy_meter_key);


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

\unrestrict lEFF4lCbBHPCenNhQMJtxiQ9f1GHQWH0TEz0MISb0QTe5skQ4zMbB2eN6Meoafd

