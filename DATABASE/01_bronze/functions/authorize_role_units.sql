-- bronze.authorize_role_units(user_role_id uuid, wanted_unit_id uuid)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.authorize_role_units(user_role_id uuid, wanted_unit_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
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
$function$
