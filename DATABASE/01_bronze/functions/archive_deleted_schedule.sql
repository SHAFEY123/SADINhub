-- bronze.archive_deleted_schedule()
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.archive_deleted_schedule()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
        $function$
