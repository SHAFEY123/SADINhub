-- Recovered from PostgreSQL server log postgresql-2026-07-30_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

        "$Table"."reading_date_saudi" as "reading_date_saudi",

        "$Table"."reading_time_saudi" as "reading_time_saudi",

        cast("$Table"."meter_id" as varchar) as "meter_id",

        "$Table"."meter" as "meter",

        cast("$Table"."zone_key" as varchar) as "zone_key",

        "$Table"."zone" as "zone",

        cast("$Table"."facility_key" as varchar) as "facility_key",

        "$Table"."facility" as "facility",

        "$Table"."voltage_average_v" as "voltage_average_v",

        "$Table"."frequency" as "frequency",

        "$Table"."power_factor_average" as "power_factor_average",

        "$Table"."voltage_imbalance_pct" as "voltage_imbalance_pct",

        "$Table"."current_imbalance_pct" as "current_imbalance_pct",

        "$Table"."voltage_status" as "voltage_status",

        "$Table"."frequency_status" as "frequency_status",

        "$Table"."power_factor_status" as "power_factor_status",

        "$Table"."overall_status" as "overall_status"

    from "gold"."power_quality" "$Table"
