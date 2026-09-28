-- View silver.energy_saving_recommendations_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.energy_saving_recommendations_landing AS
 SELECT id,
    facility_id,
    title::text COLLATE "C" AS title,
    top_right_text::text COLLATE "C" AS top_right_text,
    body_text COLLATE "C" AS body_text,
    bottom_right_text::text COLLATE "C" AS bottom_right_text,
    color::text COLLATE "C" AS color,
    icon_class::text COLLATE "C" AS icon_class,
    created_on
   FROM bronze.energy_saving_recommendations;
