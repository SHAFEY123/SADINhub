-- Recovered from PostgreSQL server log postgresql-2026-07-30_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

select "$Table"."month" as "month",

        "$Table"."year" as "year",

        "$Table"."month_number" as "month_number",

        cast("$Table"."meter_id" as varchar) as "meter_id",

        "$Table"."meter" as "meter",

        cast("$Table"."zone_key" as varchar) as "zone_key",

        "$Table"."zone" as "zone",

        cast("$Table"."facility_key" as varchar) as "facility_key",

        "$Table"."facility" as "facility",

        "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

        "$Table"."active_power_average_kw" as "active_power_average_kw",

        "$Table"."active_power_peak_kw" as "active_power_peak_kw",

        "$Table"."power_factor_average" as "power_factor_average",

        "$Table"."voltage_average_v" as "voltage_average_v",

        "$Table"."current_average_a" as "current_average_a",

        "$Table"."reading_count" as "reading_count",

        "$Table"."expected_reading_count" as "expected_reading_count",

        "$Table"."missing_reading_count" as "missing_reading_count",

        "$Table"."data_completeness_percent" as "data_completeness_percent",

        "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

    from "gold"."monthly_energy" "$Table"

    limit 100
