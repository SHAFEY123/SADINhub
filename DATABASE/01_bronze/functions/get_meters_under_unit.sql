-- bronze.get_meters_under_unit(unit_id uuid)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.get_meters_under_unit(unit_id uuid)
 RETURNS TABLE(id uuid)
 LANGUAGE plpgsql
AS $function$
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
$function$
