-- Recovered from PostgreSQL server log postgresql-2026-08-10_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

select cast("$Table"."energy_meter_key" as varchar) as "energy_meter_key",

        cast("$Table"."facility_key" as varchar) as "facility_key",

        cast("$Table"."zone_key" as varchar) as "zone_key",

        cast("$Table"."grid_billing_account_key" as varchar) as "grid_billing_account_key",

        "$Table"."reading_timestamp_utc" as "reading_timestamp_utc",

        "$Table"."active_energy_cumulative_kwh" as "active_energy_cumulative_kwh",

        "$Table"."reactive_energy_cumulative_kvarh" as "reactive_energy_cumulative_kvarh",

        "$Table"."apparent_energy_cumulative_kvah" as "apparent_energy_cumulative_kvah",

        "$Table"."voltage_neutral_1_v" as "voltage_neutral_1_v",

        "$Table"."voltage_neutral_2_v" as "voltage_neutral_2_v",

        "$Table"."voltage_neutral_3_v" as "voltage_neutral_3_v",

        "$Table"."voltage_line_1_v" as "voltage_line_1_v",

        "$Table"."voltage_line_2_v" as "voltage_line_2_v",

        "$Table"."voltage_line_3_v" as "voltage_line_3_v",

        "$Table"."current_phase_1_a" as "current_phase_1_a",

        "$Table"."current_phase_2_a" as "current_phase_2_a",

        "$Table"."current_phase_3_a" as "current_phase_3_a",

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

        "$Table"."status_vn1" as "status_vn1",

        "$Table"."status_vn2" as "status_vn2",

        "$Table"."status_vn3" as "status_vn3",

        "$Table"."status_vna" as "status_vna",

        "$Table"."status_v1" as "status_v1",

        "$Table"."status_v2" as "status_v2",

        "$Table"."status_v3" as "status_v3",

        "$Table"."status_va" as "status_va",

        "$Table"."status_amp1" as "status_amp1",

        "$Table"."status_amp2" as "status_amp2",

        "$Table"."status_amp3" as "status_amp3",

        "$Table"."status_ampa" as "status_ampa",

        "$Table"."status_hz" as "status_hz",

        "$Table"."status_pf1" as "status_pf1",

        "$Table"."status_pf2" as "status_pf2",

        "$Table"."status_pf3" as "status_pf3",

        "$Table"."status_pfa" as "status_pfa",

        "$Table"."status_kw1" as "status_kw1",

        "$Table"."status_kw2" as "status_kw2",

        "$Table"."status_kw3" as "status_kw3",

        "$Table"."status_tkw" as "status_tkw",

        "$Table"."status_kva1" as "status_kva1",

        "$Table"."status_kva2" as "status_kva2",

        "$Table"."status_kva3" as "status_kva3",

        "$Table"."status_tkva" as "status_tkva",

        "$Table"."status_kvar1" as "status_kvar1",

        "$Table"."status_kvar2" as "status_kvar2",

        "$Table"."status_kvar3" as "status_kvar3",

        "$Table"."status_tkvar" as "status_tkvar",

        "$Table"."status_kwh" as "status_kwh",

        "$Table"."status_kvah" as "status_kvah",

        "$Table"."status_kvarh" as "status_kvarh",

        "$Table"."overall_status" as "overall_status"

    from "gold"."energy_raw" "$Table"

    limit 200
