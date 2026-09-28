-- bronze.get_all_child_units_by_parent_id(src_unit_id uuid)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_all_child_units_by_parent_id(src_unit_id uuid)
 RETURNS TABLE(id uuid, name character varying, is_building boolean, level integer, parent_id uuid, type_id uuid, unit_type_name character varying)
 LANGUAGE plpgsql
AS $function$
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
$function$
