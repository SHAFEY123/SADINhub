# SADINhub database inventory

PostgreSQL 18.4, database `sadinhub`, read 2026-09-08 09:52 UTC.

## Object counts

| Schema | Kind | Count |
|---|---|---|
| bronze | functions | 29 |
| bronze | triggers | 7 |
| gold | views | 10 |
| silver | classify functions | 21 |
| silver | landing views | 107 |
| silver | materialized views | 3 |
| silver | staging views | 8 |
| silver | views | 1 |
| bronze | tables | 107 |
| silver | tables | 11 |
| gold | tables | 1 |

## Tables

| Schema | Table | Approx rows | Size |
|---|---|---:|---:|
| bronze | `addresses` | 1 | 64 kB |
| bronze | `alarm_acknowledgement_types` | - | 8192 bytes |
| bronze | `alarm_acknowledgements` | - | 32 kB |
| bronze | `alarm_configurations` | - | 40 kB |
| bronze | `alarm_configurations_history` | - | 40 kB |
| bronze | `alarm_contact_groups` | - | 24 kB |
| bronze | `alarm_contact_methods` | - | 24 kB |
| bronze | `alarm_contacts` | - | 24 kB |
| bronze | `alarm_device` | - | 32 kB |
| bronze | `alarm_device_mapping` | - | 48 kB |
| bronze | `alarm_levels` | - | 24 kB |
| bronze | `alarm_log_types` | - | 8192 bytes |
| bronze | `alarm_logs` | - | 40 kB |
| bronze | `alarm_notifications` | - | 32 kB |
| bronze | `alarm_telemetry_keys` | - | 32 kB |
| bronze | `alarm_types` | - | 24 kB |
| bronze | `alarms_severities` | - | 32 kB |
| bronze | `alarms_types` | 1 | 40 kB |
| bronze | `appliance_category` | - | 16 kB |
| bronze | `appliances` | - | 48 kB |
| bronze | `attempted_logins` | - | 24 kB |
| bronze | `banned_jtis` | - | 16 kB |
| bronze | `budget_types` | 3 | 24 kB |
| bronze | `budgets` | 1 | 72 kB |
| bronze | `clients` | 2 | 64 kB |
| bronze | `consumption_categories` | 2 | 56 kB |
| bronze | `consumption_categories_grid_billing_accounts_types` | 12 | 88 kB |
| bronze | `contact_labels` | - | 24 kB |
| bronze | `contact_method_mapping` | - | 24 kB |
| bronze | `contact_methods` | - | 24 kB |
| bronze | `contacts` | - | 48 kB |
| bronze | `deleted_schedules` | - | 48 kB |
| bronze | `device` | 91 | 344 kB |
| bronze | `device_control_labels` | - | 32 kB |
| bronze | `device_control_types` | - | 16 kB |
| bronze | `device_controls` | 270 | 264 kB |
| bronze | `device_controls_unit_pinned` | 6 | 56 kB |
| bronze | `device_credentials` | 91 | 72 kB |
| bronze | `device_sensors` | - | 80 kB |
| bronze | `device_time` | 3,800,953 | 564 MB |
| bronze | `devices_categories` | 3 | 56 kB |
| bronze | `devices_types` | 4 | 112 kB |
| bronze | `energy_bills_tracking` | 28 | 96 kB |
| bronze | `energy_meter_phase_map` | - | 24 kB |
| bronze | `energy_meters` | 32 | 144 kB |
| bronze | `energy_meters_types` | 2 | 40 kB |
| bronze | `energy_saving_recommendations` | - | 24 kB |
| bronze | `facilities` | 1 | 104 kB |
| bronze | `facilities_types` | 6 | 56 kB |
| bronze | `firmwares` | 1 | 64 kB |
| bronze | `floor_plan` | - | 48 kB |
| bronze | `forget_password` | - | 16 kB |
| bronze | `grid_billing_accounts` | 31 | 160 kB |
| bronze | `grid_billing_accounts_service_classes` | 6 | 72 kB |
| bronze | `grid_billing_accounts_types` | 6 | 40 kB |
| bronze | `icons` | - | 24 kB |
| bronze | `label_types` | 7 | 64 kB |
| bronze | `labels` | 21 | 80 kB |
| bronze | `migratehistory` | 33 | 24 kB |
| bronze | `modules` | 11 | 64 kB |
| bronze | `mqtt_service_accounts` | 7 | 96 kB |
| bronze | `mqtt_service_accounts_allowed_topics` | 20 | 72 kB |
| bronze | `mqtt_topics` | 11 | 64 kB |
| bronze | `multi_factor_authentication_factors` | - | 24 kB |
| bronze | `multi_factor_authentication_types` | 1 | 40 kB |
| bronze | `notification_types` | - | 8192 bytes |
| bronze | `notifications` | - | 40 kB |
| bronze | `overlay_controllers` | - | 24 kB |
| bronze | `overlays` | - | 64 kB |
| bronze | `permissions` | 6 | 56 kB |
| bronze | `role_module_permission` | 23 | 88 kB |
| bronze | `role_units` | 74 | 72 kB |
| bronze | `roles` | 3 | 64 kB |
| bronze | `schedule_controllers` | 474 | 144 kB |
| bronze | `schedule_jobs` | 256 | 72 kB |
| bronze | `schedule_labels` | 254 | 88 kB |
| bronze | `schedule_units` | 127 | 80 kB |
| bronze | `schedules` | 128 | 216 kB |
| bronze | `tariff_categories` | - | 32 kB |
| bronze | `telemetries` | 109,040,640 | 12 GB |
| bronze | `telemetries_dictionaries` | 58 | 40 kB |
| bronze | `telemetries_latest` | 1,008 | 192 kB |
| bronze | `telemetries_notif` | 224,764 | 82 MB |
| bronze | `telemetries_notif_users` | - | 32 kB |
| bronze | `units` | 25 | 144 kB |
| bronze | `units_types` | 7 | 96 kB |
| bronze | `upload_batch_items` | - | 32 kB |
| bronze | `upload_batches` | - | 32 kB |
| bronze | `upload_batches_types` | - | 16 kB |
| bronze | `upload_status` | - | 16 kB |
| bronze | `users` | 3 | 128 kB |
| bronze | `water_bill` | - | 40 kB |
| bronze | `water_bill_water_meter_consume` | - | 40 kB |
| bronze | `water_grid_account` | - | 72 kB |
| bronze | `water_grid_account_global_types` | - | 40 kB |
| bronze | `water_grid_account_service_class` | - | 32 kB |
| bronze | `water_grid_account_service_global` | - | 32 kB |
| bronze | `water_grid_account_service_sub_type` | - | 24 kB |
| bronze | `water_grid_account_service_type` | - | 32 kB |
| bronze | `water_grid_account_units` | - | 40 kB |
| bronze | `water_grid_provider` | - | 24 kB |
| bronze | `water_grid_water_meters` | - | 40 kB |
| bronze | `water_meter_units` | - | 40 kB |
| bronze | `water_tank` | - | 48 kB |
| bronze | `water_tank_type` | - | 16 kB |
| bronze | `water_tank_units` | - | 40 kB |
| bronze | `water_tank_water_sensors` | - | 80 kB |
| gold | `energy_reading_gaps` | 963 | 136 kB |
| silver | `agg_energy_1d` | 15,768 | 22 MB |
| silver | `agg_energy_1h` | 377,346 | 810 MB |
| silver | `agg_energy_1month` | 593 | 552 kB |
| silver | `agg_energy_1week` | 2,338 | 2024 kB |
| silver | `agg_energy_30min` | 752,833 | 1619 MB |
| silver | `agg_energy_3d` | 5,316 | 4528 kB |
| silver | `agg_energy_4h` | 93,875 | 130 MB |
| silver | `data_quality_summary` | - | 32 kB |
| silver | `dim_meter_cb_rating` | - | 24 kB |
| silver | `fact_energy_consumption_validated` | 4,260,248 | 1221 MB |
| silver | `fact_energy_readings_snapshot` | 4,535,675 | 2287 MB |

## Views and materialised views

| Schema | Name | Kind |
|---|---|---|
| gold | `billing_account` | view |
| gold | `date` | view |
| gold | `energy_bill` | view |
| gold | `energy_consumption_validated` | view |
| gold | `energy_raw` | view |
| gold | `facility` | view |
| gold | `mapping_audit` | view |
| gold | `meter` | view |
| gold | `quality_summary` | view |
| gold | `zone` | view |
| silver | `addresses_landing` | view |
| silver | `alarm_acknowledgement_types_landing` | view |
| silver | `alarm_acknowledgements_landing` | view |
| silver | `alarm_configurations_history_landing` | view |
| silver | `alarm_configurations_landing` | view |
| silver | `alarm_contact_groups_landing` | view |
| silver | `alarm_contact_methods_landing` | view |
| silver | `alarm_contacts_landing` | view |
| silver | `alarm_device_landing` | view |
| silver | `alarm_device_mapping_landing` | view |
| silver | `alarm_levels_landing` | view |
| silver | `alarm_log_types_landing` | view |
| silver | `alarm_logs_landing` | view |
| silver | `alarm_notifications_landing` | view |
| silver | `alarm_telemetry_keys_landing` | view |
| silver | `alarm_types_landing` | view |
| silver | `alarms_severities_landing` | view |
| silver | `alarms_types_landing` | view |
| silver | `appliance_category_landing` | view |
| silver | `appliances_landing` | view |
| silver | `attempted_logins_landing` | view |
| silver | `banned_jtis_landing` | view |
| silver | `budget_types_landing` | view |
| silver | `budgets_landing` | view |
| silver | `clients_landing` | view |
| silver | `consumption_categories_grid_billing_accounts_types_landing` | view |
| silver | `consumption_categories_landing` | view |
| silver | `contact_labels_landing` | view |
| silver | `contact_method_mapping_landing` | view |
| silver | `contact_methods_landing` | view |
| silver | `contacts_landing` | view |
| silver | `deleted_schedules_landing` | view |
| silver | `device_control_labels_landing` | view |
| silver | `device_control_types_landing` | view |
| silver | `device_controls_landing` | view |
| silver | `device_controls_unit_pinned_landing` | view |
| silver | `device_credentials_landing` | view |
| silver | `device_landing` | view |
| silver | `device_sensors_landing` | view |
| silver | `device_time_landing` | view |
| silver | `devices_categories_landing` | view |
| silver | `devices_types_landing` | view |
| silver | `dim_date_staging` | view |
| silver | `dim_energy_meter_staging` | view |
| silver | `dim_facility_staging` | view |
| silver | `dim_grid_billing_account_staging` | view |
| silver | `dim_zone_staging` | view |
| silver | `dq_device_cadence_staging` | materialised view |
| silver | `dq_meter_daily_completeness_staging` | materialised view |
| silver | `dq_missing_intervals_staging` | materialised view |
| silver | `energy_bills_tracking_landing` | view |
| silver | `energy_meter_mapping_audit_staging` | view |
| silver | `energy_meter_phase_map_landing` | view |
| silver | `energy_meters_landing` | view |
| silver | `energy_meters_types_landing` | view |
| silver | `energy_saving_recommendations_landing` | view |
| silver | `facilities_landing` | view |
| silver | `facilities_types_landing` | view |
| silver | `fact_energy_bill_staging` | view |
| silver | `fact_energy_readings_flagged` | view |
| silver | `fact_energy_readings_staging` | view |
| silver | `firmwares_landing` | view |
| silver | `floor_plan_landing` | view |
| silver | `forget_password_landing` | view |
| silver | `grid_billing_accounts_landing` | view |
| silver | `grid_billing_accounts_service_classes_landing` | view |
| silver | `grid_billing_accounts_types_landing` | view |
| silver | `icons_landing` | view |
| silver | `label_types_landing` | view |
| silver | `labels_landing` | view |
| silver | `migratehistory_landing` | view |
| silver | `modules_landing` | view |
| silver | `mqtt_service_accounts_allowed_topics_landing` | view |
| silver | `mqtt_service_accounts_landing` | view |
| silver | `mqtt_topics_landing` | view |
| silver | `multi_factor_authentication_factors_landing` | view |
| silver | `multi_factor_authentication_types_landing` | view |
| silver | `notification_types_landing` | view |
| silver | `notifications_landing` | view |
| silver | `overlay_controllers_landing` | view |
| silver | `overlays_landing` | view |
| silver | `permissions_landing` | view |
| silver | `role_module_permission_landing` | view |
| silver | `role_units_landing` | view |
| silver | `roles_landing` | view |
| silver | `schedule_controllers_landing` | view |
| silver | `schedule_jobs_landing` | view |
| silver | `schedule_labels_landing` | view |
| silver | `schedule_units_landing` | view |
| silver | `schedules_landing` | view |
| silver | `tariff_categories_landing` | view |
| silver | `telemetries_dictionaries_landing` | view |
| silver | `telemetries_landing` | view |
| silver | `telemetries_latest_landing` | view |
| silver | `telemetries_notif_landing` | view |
| silver | `telemetries_notif_users_landing` | view |
| silver | `units_landing` | view |
| silver | `units_types_landing` | view |
| silver | `upload_batch_items_landing` | view |
| silver | `upload_batches_landing` | view |
| silver | `upload_batches_types_landing` | view |
| silver | `upload_status_landing` | view |
| silver | `users_landing` | view |
| silver | `water_bill_landing` | view |
| silver | `water_bill_water_meter_consume_landing` | view |
| silver | `water_grid_account_global_types_landing` | view |
| silver | `water_grid_account_landing` | view |
| silver | `water_grid_account_service_class_landing` | view |
| silver | `water_grid_account_service_global_landing` | view |
| silver | `water_grid_account_service_sub_type_landing` | view |
| silver | `water_grid_account_service_type_landing` | view |
| silver | `water_grid_account_units_landing` | view |
| silver | `water_grid_provider_landing` | view |
| silver | `water_grid_water_meters_landing` | view |
| silver | `water_meter_units_landing` | view |
| silver | `water_tank_landing` | view |
| silver | `water_tank_type_landing` | view |
| silver | `water_tank_units_landing` | view |
| silver | `water_tank_water_sensors_landing` | view |

## Functions and procedures

| Schema | Routine |
|---|---|
| bronze | `add_alarm_to_device()` |
| bronze | `archive_deleted_schedule()` |
| bronze | `assign_role_to_all_units()` |
| bronze | `authorize_role_units(user_role_id uuid, wanted_unit_id uuid)` |
| bronze | `calc_meter_consume(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text)` |
| bronze | `calc_meter_consume_with_start_end_consume_info(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text)` |
| bronze | `check_facility_budget_duplication()` |
| bronze | `check_facility_id_not_null()` |
| bronze | `check_sensor_in_device_sensors()` |
| bronze | `check_sensor_in_tank_sensors()` |
| bronze | `device_on_off_run_time(new_device_online boolean, new_device_id uuid, new_timestamp bigint, new_value double precision, new_telemetry_key_name text)` |
| bronze | `fetch_user_permissions(user_role_id uuid)` |
| bronze | `get_all_child_units_by_parent_id(src_unit_id uuid)` |
| bronze | `get_each_day_consume_per_units(days_timestamps jsonb)` |
| bronze | `get_latest_telemetry(in_device_id uuid, telemetrie_key_name text)` |
| bronze | `get_meters_consumption_in_different_timestamps(start_end_timestamps bigint[], devices uuid[], tele_key text)` |
| bronze | `get_meters_consumption_in_different_timestamps_with_sar_cost(cycle_data json[], start_end_timestamps bigint[], devices uuid[], tele_key integer)` |
| bronze | `get_meters_consumption_in_range(meter_ids uuid[], input_start_timestamp bigint, input_end_timestamp bigint)` |
| bronze | `get_meters_runtime(meters_list uuid[], start_timestamp bigint, end_timestamp bigint)` |
| bronze | `get_meters_under_unit(unit_id uuid)` |
| bronze | `get_telemetries_key_id_by_key_name(key_name text)` |
| bronze | `get_uniform_dbl_data_per_device_1_timestamp(device_1 text, devices text[], tele_key integer, start_timestamp bigint, end_timestamp bigint)` |
| bronze | `get_working_custom_groups_consume_per_units(custom_groups_timestamps jsonb)` |
| bronze | `get_working_non_working_days_consume_per_units(working_non_working_hours_timestamps jsonb)` |
| bronze | `initialize_init_on_off_run_time_for_all_devices()` |
| bronze | `link_unit_with_parent_roles()` |
| bronze | `query_calc_meter_consume(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text)` |
| bronze | `query_calc_meter_consume_with_start_end_consume_info(start_timestamp bigint, end_timestamp bigint, meter_id uuid, telemetry_key text)` |
| bronze | `unit_recursion_info(_unit_id uuid)` |
| silver | `classify_accumulated_energy_v2(value double precision, prev_value double precision)` |
| silver | `classify_active_power(p_value double precision, p_prev_value double precision, p_cb_max_kw double precision)` |
| silver | `classify_apparent_power(p_value double precision, p_prev_value double precision, p_user_max double precision)` |
| silver | `classify_consistency(p_total double precision, p_phase_sum double precision, p_tolerance_pct double precision)` |
| silver | `classify_current(p_value double precision, p_prev_value double precision, p_cb_max_a double precision)` |
| silver | `classify_current_v2(value double precision, cb_max double precision)` |
| silver | `classify_current_v2(value double precision, cb_max double precision, phase_kw double precision)` |
| silver | `classify_energy(p_value double precision, p_prev_value double precision, p_user_max double precision)` |
| silver | `classify_frequency(p_value double precision, p_prev_value double precision)` |
| silver | `classify_frequency_v2(value double precision)` |
| silver | `classify_phase_imbalance(p_imbalance_pct double precision, p_evaluation_status text, p_problematic_threshold_pct double precision, p_critical_threshold_pct double precision)` |
| silver | `classify_power_factor(p_value double precision, p_prev_value double precision, p_spike_pct double precision)` |
| silver | `classify_power_factor_v2(value double precision)` |
| silver | `classify_reactive_power(p_value double precision, p_prev_value double precision)` |
| silver | `classify_standard(p_value double precision, p_prev_value double precision, p_hard_min double precision, p_hard_max double precision, p_acceptable_min double precision, p_acceptable_max double precision, p_invalid_min double precision, p_invalid_max double precision, p_spike_pct double precision)` |
| silver | `classify_voltage_line(p_value double precision, p_prev_value double precision)` |
| silver | `classify_voltage_line_v2(value double precision)` |
| silver | `classify_voltage_neutral(p_value double precision, p_prev_value double precision)` |
| silver | `classify_voltage_neutral_v2(value double precision)` |
| silver | `status_rank(p_status text)` |
| silver | `worst_status(VARIADIC p_statuses text[])` |

## Triggers

| Schema | Table | Trigger |
|---|---|---|
| bronze | `budgets` | `check_facility_budget_duplication_constraint` |
| bronze | `device` | `add_alarm_to_device_constraint` |
| bronze | `device_sensors` | `check_sensor_in_tank_sensors_constraint` |
| bronze | `schedules` | `before_delete_schedule` |
| bronze | `units` | `add_unit_role` |
| bronze | `users` | `check_facility_id_not_null_unit_constraint` |
| bronze | `water_tank_water_sensors` | `check_sensor_in_device_sensors_constraint` |
