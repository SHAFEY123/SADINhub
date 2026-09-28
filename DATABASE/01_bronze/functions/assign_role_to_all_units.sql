-- bronze.assign_role_to_all_units()
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE PROCEDURE bronze.assign_role_to_all_units()
 LANGUAGE plpgsql
AS $procedure$
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
END; $procedure$
