-- Views in dependency order
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze, silver, gold
-- Source of truth: pg_depend - each view listed after everything it reads
-- VIEWS ONLY. Requires schemas, tables, sequences and routines first.
-- This is NOT a complete database restore script.
-- Prefer pg_dump/schema_full.sql for a new empty database.


--   1. gold.energy_consumption_validated   (views)
\ir 03_gold/views/energy_consumption_validated.sql
--   2. gold.energy_raw   (views)
\ir 03_gold/views/energy_raw.sql
--   3. gold.quality_summary   (views)
\ir 03_gold/views/quality_summary.sql
--   4. silver.addresses_landing   (landing_views)
\ir 02_silver/landing_views/addresses_landing.sql
--   5. silver.alarm_acknowledgement_types_landing   (landing_views)
\ir 02_silver/landing_views/alarm_acknowledgement_types_landing.sql
--   6. silver.alarm_acknowledgements_landing   (landing_views)
\ir 02_silver/landing_views/alarm_acknowledgements_landing.sql
--   7. silver.alarm_configurations_history_landing   (landing_views)
\ir 02_silver/landing_views/alarm_configurations_history_landing.sql
--   8. silver.alarm_configurations_landing   (landing_views)
\ir 02_silver/landing_views/alarm_configurations_landing.sql
--   9. silver.alarm_contact_groups_landing   (landing_views)
\ir 02_silver/landing_views/alarm_contact_groups_landing.sql
--  10. silver.alarm_contact_methods_landing   (landing_views)
\ir 02_silver/landing_views/alarm_contact_methods_landing.sql
--  11. silver.alarm_contacts_landing   (landing_views)
\ir 02_silver/landing_views/alarm_contacts_landing.sql
--  12. silver.alarm_device_landing   (landing_views)
\ir 02_silver/landing_views/alarm_device_landing.sql
--  13. silver.alarm_device_mapping_landing   (landing_views)
\ir 02_silver/landing_views/alarm_device_mapping_landing.sql
--  14. silver.alarm_levels_landing   (landing_views)
\ir 02_silver/landing_views/alarm_levels_landing.sql
--  15. silver.alarm_log_types_landing   (landing_views)
\ir 02_silver/landing_views/alarm_log_types_landing.sql
--  16. silver.alarm_logs_landing   (landing_views)
\ir 02_silver/landing_views/alarm_logs_landing.sql
--  17. silver.alarm_notifications_landing   (landing_views)
\ir 02_silver/landing_views/alarm_notifications_landing.sql
--  18. silver.alarm_telemetry_keys_landing   (landing_views)
\ir 02_silver/landing_views/alarm_telemetry_keys_landing.sql
--  19. silver.alarm_types_landing   (landing_views)
\ir 02_silver/landing_views/alarm_types_landing.sql
--  20. silver.alarms_severities_landing   (landing_views)
\ir 02_silver/landing_views/alarms_severities_landing.sql
--  21. silver.alarms_types_landing   (landing_views)
\ir 02_silver/landing_views/alarms_types_landing.sql
--  22. silver.appliance_category_landing   (landing_views)
\ir 02_silver/landing_views/appliance_category_landing.sql
--  23. silver.appliances_landing   (landing_views)
\ir 02_silver/landing_views/appliances_landing.sql
--  24. silver.attempted_logins_landing   (landing_views)
\ir 02_silver/landing_views/attempted_logins_landing.sql
--  25. silver.banned_jtis_landing   (landing_views)
\ir 02_silver/landing_views/banned_jtis_landing.sql
--  26. silver.budget_types_landing   (landing_views)
\ir 02_silver/landing_views/budget_types_landing.sql
--  27. silver.budgets_landing   (landing_views)
\ir 02_silver/landing_views/budgets_landing.sql
--  28. silver.clients_landing   (landing_views)
\ir 02_silver/landing_views/clients_landing.sql
--  29. silver.consumption_categories_grid_billing_accounts_types_landing   (landing_views)
\ir 02_silver/landing_views/consumption_categories_grid_billing_accounts_types_landing.sql
--  30. silver.consumption_categories_landing   (landing_views)
\ir 02_silver/landing_views/consumption_categories_landing.sql
--  31. silver.contact_labels_landing   (landing_views)
\ir 02_silver/landing_views/contact_labels_landing.sql
--  32. silver.contact_method_mapping_landing   (landing_views)
\ir 02_silver/landing_views/contact_method_mapping_landing.sql
--  33. silver.contact_methods_landing   (landing_views)
\ir 02_silver/landing_views/contact_methods_landing.sql
--  34. silver.contacts_landing   (landing_views)
\ir 02_silver/landing_views/contacts_landing.sql
--  35. silver.deleted_schedules_landing   (landing_views)
\ir 02_silver/landing_views/deleted_schedules_landing.sql
--  36. silver.device_control_labels_landing   (landing_views)
\ir 02_silver/landing_views/device_control_labels_landing.sql
--  37. silver.device_control_types_landing   (landing_views)
\ir 02_silver/landing_views/device_control_types_landing.sql
--  38. silver.device_controls_landing   (landing_views)
\ir 02_silver/landing_views/device_controls_landing.sql
--  39. silver.device_controls_unit_pinned_landing   (landing_views)
\ir 02_silver/landing_views/device_controls_unit_pinned_landing.sql
--  40. silver.device_credentials_landing   (landing_views)
\ir 02_silver/landing_views/device_credentials_landing.sql
--  41. silver.device_landing   (landing_views)
\ir 02_silver/landing_views/device_landing.sql
--  42. silver.device_sensors_landing   (landing_views)
\ir 02_silver/landing_views/device_sensors_landing.sql
--  43. silver.device_time_landing   (landing_views)
\ir 02_silver/landing_views/device_time_landing.sql
--  44. silver.devices_categories_landing   (landing_views)
\ir 02_silver/landing_views/devices_categories_landing.sql
--  45. silver.devices_types_landing   (landing_views)
\ir 02_silver/landing_views/devices_types_landing.sql
--  46. silver.dim_date_staging   (staging_views)
\ir 02_silver/staging_views/dim_date_staging.sql
--  47. silver.energy_bills_tracking_landing   (landing_views)
\ir 02_silver/landing_views/energy_bills_tracking_landing.sql
--  48. silver.energy_meter_phase_map_landing   (landing_views)
\ir 02_silver/landing_views/energy_meter_phase_map_landing.sql
--  49. silver.energy_meters_landing   (landing_views)
\ir 02_silver/landing_views/energy_meters_landing.sql
--  50. silver.energy_meters_types_landing   (landing_views)
\ir 02_silver/landing_views/energy_meters_types_landing.sql
--  51. silver.energy_saving_recommendations_landing   (landing_views)
\ir 02_silver/landing_views/energy_saving_recommendations_landing.sql
--  52. silver.facilities_landing   (landing_views)
\ir 02_silver/landing_views/facilities_landing.sql
--  53. silver.facilities_types_landing   (landing_views)
\ir 02_silver/landing_views/facilities_types_landing.sql
--  54. silver.firmwares_landing   (landing_views)
\ir 02_silver/landing_views/firmwares_landing.sql
--  55. silver.floor_plan_landing   (landing_views)
\ir 02_silver/landing_views/floor_plan_landing.sql
--  56. silver.forget_password_landing   (landing_views)
\ir 02_silver/landing_views/forget_password_landing.sql
--  57. silver.grid_billing_accounts_landing   (landing_views)
\ir 02_silver/landing_views/grid_billing_accounts_landing.sql
--  58. silver.grid_billing_accounts_service_classes_landing   (landing_views)
\ir 02_silver/landing_views/grid_billing_accounts_service_classes_landing.sql
--  59. silver.grid_billing_accounts_types_landing   (landing_views)
\ir 02_silver/landing_views/grid_billing_accounts_types_landing.sql
--  60. silver.icons_landing   (landing_views)
\ir 02_silver/landing_views/icons_landing.sql
--  61. silver.label_types_landing   (landing_views)
\ir 02_silver/landing_views/label_types_landing.sql
--  62. silver.labels_landing   (landing_views)
\ir 02_silver/landing_views/labels_landing.sql
--  63. silver.migratehistory_landing   (landing_views)
\ir 02_silver/landing_views/migratehistory_landing.sql
--  64. silver.modules_landing   (landing_views)
\ir 02_silver/landing_views/modules_landing.sql
--  65. silver.mqtt_service_accounts_allowed_topics_landing   (landing_views)
\ir 02_silver/landing_views/mqtt_service_accounts_allowed_topics_landing.sql
--  66. silver.mqtt_service_accounts_landing   (landing_views)
\ir 02_silver/landing_views/mqtt_service_accounts_landing.sql
--  67. silver.mqtt_topics_landing   (landing_views)
\ir 02_silver/landing_views/mqtt_topics_landing.sql
--  68. silver.multi_factor_authentication_factors_landing   (landing_views)
\ir 02_silver/landing_views/multi_factor_authentication_factors_landing.sql
--  69. silver.multi_factor_authentication_types_landing   (landing_views)
\ir 02_silver/landing_views/multi_factor_authentication_types_landing.sql
--  70. silver.notification_types_landing   (landing_views)
\ir 02_silver/landing_views/notification_types_landing.sql
--  71. silver.notifications_landing   (landing_views)
\ir 02_silver/landing_views/notifications_landing.sql
--  72. silver.overlay_controllers_landing   (landing_views)
\ir 02_silver/landing_views/overlay_controllers_landing.sql
--  73. silver.overlays_landing   (landing_views)
\ir 02_silver/landing_views/overlays_landing.sql
--  74. silver.permissions_landing   (landing_views)
\ir 02_silver/landing_views/permissions_landing.sql
--  75. silver.role_module_permission_landing   (landing_views)
\ir 02_silver/landing_views/role_module_permission_landing.sql
--  76. silver.role_units_landing   (landing_views)
\ir 02_silver/landing_views/role_units_landing.sql
--  77. silver.roles_landing   (landing_views)
\ir 02_silver/landing_views/roles_landing.sql
--  78. silver.schedule_controllers_landing   (landing_views)
\ir 02_silver/landing_views/schedule_controllers_landing.sql
--  79. silver.schedule_jobs_landing   (landing_views)
\ir 02_silver/landing_views/schedule_jobs_landing.sql
--  80. silver.schedule_labels_landing   (landing_views)
\ir 02_silver/landing_views/schedule_labels_landing.sql
--  81. silver.schedule_units_landing   (landing_views)
\ir 02_silver/landing_views/schedule_units_landing.sql
--  82. silver.schedules_landing   (landing_views)
\ir 02_silver/landing_views/schedules_landing.sql
--  83. silver.tariff_categories_landing   (landing_views)
\ir 02_silver/landing_views/tariff_categories_landing.sql
--  84. silver.telemetries_dictionaries_landing   (landing_views)
\ir 02_silver/landing_views/telemetries_dictionaries_landing.sql
--  85. silver.telemetries_landing   (landing_views)
\ir 02_silver/landing_views/telemetries_landing.sql
--  86. silver.telemetries_latest_landing   (landing_views)
\ir 02_silver/landing_views/telemetries_latest_landing.sql
--  87. silver.telemetries_notif_landing   (landing_views)
\ir 02_silver/landing_views/telemetries_notif_landing.sql
--  88. silver.telemetries_notif_users_landing   (landing_views)
\ir 02_silver/landing_views/telemetries_notif_users_landing.sql
--  89. silver.units_landing   (landing_views)
\ir 02_silver/landing_views/units_landing.sql
--  90. silver.units_types_landing   (landing_views)
\ir 02_silver/landing_views/units_types_landing.sql
--  91. silver.upload_batch_items_landing   (landing_views)
\ir 02_silver/landing_views/upload_batch_items_landing.sql
--  92. silver.upload_batches_landing   (landing_views)
\ir 02_silver/landing_views/upload_batches_landing.sql
--  93. silver.upload_batches_types_landing   (landing_views)
\ir 02_silver/landing_views/upload_batches_types_landing.sql
--  94. silver.upload_status_landing   (landing_views)
\ir 02_silver/landing_views/upload_status_landing.sql
--  95. silver.users_landing   (landing_views)
\ir 02_silver/landing_views/users_landing.sql
--  96. silver.water_bill_landing   (landing_views)
\ir 02_silver/landing_views/water_bill_landing.sql
--  97. silver.water_bill_water_meter_consume_landing   (landing_views)
\ir 02_silver/landing_views/water_bill_water_meter_consume_landing.sql
--  98. silver.water_grid_account_global_types_landing   (landing_views)
\ir 02_silver/landing_views/water_grid_account_global_types_landing.sql
--  99. silver.water_grid_account_landing   (landing_views)
\ir 02_silver/landing_views/water_grid_account_landing.sql
-- 100. silver.water_grid_account_service_class_landing   (landing_views)
\ir 02_silver/landing_views/water_grid_account_service_class_landing.sql
-- 101. silver.water_grid_account_service_global_landing   (landing_views)
\ir 02_silver/landing_views/water_grid_account_service_global_landing.sql
-- 102. silver.water_grid_account_service_sub_type_landing   (landing_views)
\ir 02_silver/landing_views/water_grid_account_service_sub_type_landing.sql
-- 103. silver.water_grid_account_service_type_landing   (landing_views)
\ir 02_silver/landing_views/water_grid_account_service_type_landing.sql
-- 104. silver.water_grid_account_units_landing   (landing_views)
\ir 02_silver/landing_views/water_grid_account_units_landing.sql
-- 105. silver.water_grid_provider_landing   (landing_views)
\ir 02_silver/landing_views/water_grid_provider_landing.sql
-- 106. silver.water_grid_water_meters_landing   (landing_views)
\ir 02_silver/landing_views/water_grid_water_meters_landing.sql
-- 107. silver.water_meter_units_landing   (landing_views)
\ir 02_silver/landing_views/water_meter_units_landing.sql
-- 108. silver.water_tank_landing   (landing_views)
\ir 02_silver/landing_views/water_tank_landing.sql
-- 109. silver.water_tank_type_landing   (landing_views)
\ir 02_silver/landing_views/water_tank_type_landing.sql
-- 110. silver.water_tank_units_landing   (landing_views)
\ir 02_silver/landing_views/water_tank_units_landing.sql
-- 111. silver.water_tank_water_sensors_landing   (landing_views)
\ir 02_silver/landing_views/water_tank_water_sensors_landing.sql
-- 112. gold.date   (views)
\ir 03_gold/views/date.sql
-- 113. silver.dim_facility_staging   (staging_views)
\ir 02_silver/staging_views/dim_facility_staging.sql
-- 114. silver.dim_grid_billing_account_staging   (staging_views)
\ir 02_silver/staging_views/dim_grid_billing_account_staging.sql
-- 115. silver.dim_energy_meter_staging   (staging_views)
\ir 02_silver/staging_views/dim_energy_meter_staging.sql
-- 116. silver.energy_meter_mapping_audit_staging   (staging_views)
\ir 02_silver/staging_views/energy_meter_mapping_audit_staging.sql
-- 117. silver.dim_zone_staging   (staging_views)
\ir 02_silver/staging_views/dim_zone_staging.sql
-- 118. gold.facility   (views)
\ir 03_gold/views/facility.sql
-- 119. gold.billing_account   (views)
\ir 03_gold/views/billing_account.sql
-- 120. silver.fact_energy_bill_staging   (staging_views)
\ir 02_silver/staging_views/fact_energy_bill_staging.sql
-- 121. gold.meter   (views)
\ir 03_gold/views/meter.sql
-- 122. silver.fact_energy_readings_staging   (staging_views)
\ir 02_silver/staging_views/fact_energy_readings_staging.sql
-- 123. gold.mapping_audit   (views)
\ir 03_gold/views/mapping_audit.sql
-- 124. gold.zone   (views)
\ir 03_gold/views/zone.sql
-- 125. silver.dq_device_cadence_staging   (materialized_views)
\ir 02_silver/materialized_views/dq_device_cadence_staging.sql
-- 126. gold.energy_bill   (views)
\ir 03_gold/views/energy_bill.sql
-- 127. silver.fact_energy_readings_flagged   (views)
\ir 02_silver/views/fact_energy_readings_flagged.sql
-- 128. silver.dq_meter_daily_completeness_staging   (materialized_views)
\ir 02_silver/materialized_views/dq_meter_daily_completeness_staging.sql
-- 129. silver.dq_missing_intervals_staging   (materialized_views)
\ir 02_silver/materialized_views/dq_missing_intervals_staging.sql
