-- Recovered from PostgreSQL server log postgresql-2026-07-30_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

select cast("$Table"."energy_meter_key" as varchar) as "energy_meter_key",

        cast("$Table"."source_energy_meter_id" as varchar) as "source_energy_meter_id",

        cast("$Table"."facility_key" as varchar) as "facility_key",

        cast("$Table"."zone_key" as varchar) as "zone_key",

        cast("$Table"."grid_billing_account_key" as varchar) as "grid_billing_account_key",

        "$Table"."date_key" as "date_key",

        "$Table"."time_key" as "time_key",

        "$Table"."source_timestamp_ms" as "source_timestamp_ms",

        "$Table"."reading_timestamp_utc" as "reading_timestamp_utc",

        "$Table"."voltage_line_1_v" as "voltage_line_1_v",

        "$Table"."voltage_line_2_v" as "voltage_line_2_v",

        "$Table"."voltage_line_3_v" as "voltage_line_3_v",

        "$Table"."voltage_line_average_v" as "voltage_line_average_v",

        "$Table"."voltage_neutral_1_v" as "voltage_neutral_1_v",

        "$Table"."voltage_neutral_2_v" as "voltage_neutral_2_v",

        "$Table"."voltage_neutral_3_v" as "voltage_neutral_3_v",

        "$Table"."voltage_neutral_average_v" as "voltage_neutral_average_v",

        "$Table"."current_phase_1_a" as "current_phase_1_a",

        "$Table"."current_phase_2_a" as "current_phase_2_a",

        "$Table"."current_phase_3_a" as "current_phase_3_a",

        "$Table"."current_average_a" as "current_average_a",

        "$Table"."frequency_hz" as "frequency_hz",

        "$Table"."power_factor_phase_1" as "power_factor_phase_1",

        "$Table"."power_factor_phase_2" as "power_factor_phase_2",

        "$Table"."power_factor_phase_3" as "power_factor_phase_3",

        "$Table"."power_factor_average" as "power_factor_average",

        "$Table"."active_power_phase_1_kw" as "active_power_phase_1_kw",

        "$Table"."active_power_phase_2_kw" as "active_power_phase_2_kw",

        "$Table"."active_power_phase_3_kw" as "active_power_phase_3_kw",

        "$Table"."active_power_total_kw" as "active_power_total_kw",

        "$Table"."apparent_power_phase_1_kva" as "apparent_power_phase_1_kva",

        "$Table"."apparent_power_phase_2_kva" as "apparent_power_phase_2_kva",

        "$Table"."apparent_power_phase_3_kva" as "apparent_power_phase_3_kva",

        "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

        "$Table"."reactive_power_phase_1_kvar" as "reactive_power_phase_1_kvar",

        "$Table"."reactive_power_phase_2_kvar" as "reactive_power_phase_2_kvar",

        "$Table"."reactive_power_phase_3_kvar" as "reactive_power_phase_3_kvar",

        "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

        "$Table"."active_energy_cumulative_kwh" as "active_energy_cumulative_kwh",

        "$Table"."apparent_energy_cumulative_kvah" as "apparent_energy_cumulative_kvah",

        "$Table"."reactive_energy_cumulative_kvarh" as "reactive_energy_cumulative_kvarh",

        "$Table"."source_measurement_row_count" as "source_measurement_row_count",

        "$Table"."populated_measurement_count" as "populated_measurement_count",

        "$Table"."duplicate_measurement_row_count" as "duplicate_measurement_row_count",

        "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

        "$Table"."reading_date_saudi" as "reading_date_saudi",

        "$Table"."reading_time_saudi" as "reading_time_saudi",

        "$Table"."saudi_date_key" as "saudi_date_key",

        "$Table"."saudi_time_key" as "saudi_time_key",

        "$Table"."calculated_current_average_a" as "calculated_current_average_a",

        "$Table"."current_phase_spread_a" as "current_phase_spread_a",

        "$Table"."current_imbalance_pct" as "current_imbalance_pct",

        "$Table"."current_imbalance_evaluation_status" as "current_imbalance_evaluation_status",

        "$Table"."calculated_voltage_average_v" as "calculated_voltage_average_v",

        "$Table"."voltage_phase_spread_v" as "voltage_phase_spread_v",

        "$Table"."voltage_imbalance_pct" as "voltage_imbalance_pct",

        "$Table"."voltage_imbalance_evaluation_status" as "voltage_imbalance_evaluation_status"

    from "gold"."energy_reading" "$Table"

    limit 1000
