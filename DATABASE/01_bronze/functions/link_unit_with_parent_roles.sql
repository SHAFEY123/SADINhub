-- bronze.link_unit_with_parent_roles()
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.link_unit_with_parent_roles()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$
