-- Recovered from PostgreSQL server log postgresql-2026-07-30_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

select "$Table"."date" as "date",

        "$Table"."date_key" as "date_key",

        cast("$Table"."meter_id" as varchar) as "meter_id",

        "$Table"."meter" as "meter",

        cast("$Table"."zone_key" as varchar) as "zone_key",

        "$Table"."zone" as "zone",

        cast("$Table"."facility_key" as varchar) as "facility_key",

        "$Table"."facility" as "facility",

        "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

        "$Table"."active_power_average_kw" as "active_power_average_kw",

        "$Table"."active_power_peak_kw" as "active_power_peak_kw",

        "$Table"."active_power_minimum_kw" as "active_power_minimum_kw",

        "$Table"."power_factor_average" as "power_factor_average",

        "$Table"."voltage_average_v" as "voltage_average_v",

        "$Table"."current_average_a" as "current_average_a",

        "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

        "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

        "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

        "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

        "$Table"."reading_count" as "reading_count",

        "$Table"."expected_reading_count" as "expected_reading_count",

        "$Table"."missing_reading_count" as "missing_reading_count",

        "$Table"."data_completeness_percent" as "data_completeness_percent",

        "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

    from "gold"."daily_energy" "$Table"

    limit 1000
