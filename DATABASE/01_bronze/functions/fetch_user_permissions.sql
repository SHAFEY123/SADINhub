-- bronze.fetch_user_permissions(user_role_id uuid)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.fetch_user_permissions(user_role_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
