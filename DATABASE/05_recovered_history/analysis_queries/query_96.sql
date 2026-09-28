-- Recovered from PostgreSQL server log postgresql-2026-07-30_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

        "$Table"."reading_date_saudi" as "reading_date_saudi",

        "$Table"."reading_time_saudi" as "reading_time_saudi",

        "$Table"."saudi_date_key" as "saudi_date_key",

        "$Table"."saudi_time_key" as "saudi_time_key",

        cast("$Table"."facility_key" as varchar) as "facility_key",

        "$Table"."facility" as "facility",

        "$Table"."zone_count" as "zone_count",

        "$Table"."meter_count" as "meter_count",

        "$Table"."active_power_total_kw" as "active_power_total_kw",

        "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

        "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

        "$Table"."power_factor_average" as "power_factor_average",

        "$Table"."frequency_average_hz" as "frequency_average_hz",

        "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

        "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

        "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

        "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

        "$Table"."aggregation_status" as "aggregation_status"

    from "gold"."facility_reading" "$Table"
