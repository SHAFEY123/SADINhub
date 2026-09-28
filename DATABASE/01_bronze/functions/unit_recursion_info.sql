-- bronze.unit_recursion_info(_unit_id uuid)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.unit_recursion_info(_unit_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
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
$function$
