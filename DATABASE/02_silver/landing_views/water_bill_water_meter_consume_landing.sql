-- View silver.water_bill_water_meter_consume_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.water_bill_water_meter_consume_landing AS
 SELECT water_bill_id,
    water_meter_id,
        CASE
            WHEN water_meter_consume IS NULL THEN NULL::real
            ELSE round(water_meter_consume::numeric, 6)::real
        END AS water_meter_consume,
    created_on,
    created_by
   FROM bronze.water_bill_water_meter_consume;
