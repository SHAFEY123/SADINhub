-- bronze.add_alarm_to_device()
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.add_alarm_to_device()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$
