-- Recovered from PostgreSQL server log postgresql-2026-07-30_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

select "$Table"."date" as "date",

        cast("$Table"."meter_id" as varchar) as "meter_id",

        "$Table"."meter" as "meter",

        cast("$Table"."zone_key" as varchar) as "zone_key",

        "$Table"."zone" as "zone",

        cast("$Table"."facility_key" as varchar) as "facility_key",

        "$Table"."facility" as "facility",

        "$Table"."peak_active_power_kw" as "peak_active_power_kw",

        "$Table"."peak_timestamp_saudi" as "peak_timestamp_saudi",

        "$Table"."average_active_power_kw" as "average_active_power_kw",

        "$Table"."minimum_active_power_kw" as "minimum_active_power_kw",

        "$Table"."load_factor_percent" as "load_factor_percent"

    from "gold"."peak_demand" "$Table"

    limit 1000
