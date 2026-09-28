-- bronze.initialize_init_on_off_run_time_for_all_devices()
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE PROCEDURE bronze.initialize_init_on_off_run_time_for_all_devices()
 LANGUAGE plpgsql
AS $procedure$
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
END; $procedure$
