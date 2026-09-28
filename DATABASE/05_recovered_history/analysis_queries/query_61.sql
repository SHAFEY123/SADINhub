-- Recovered from PostgreSQL server log postgresql-2026-07-30_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

select cast("$Table"."meter_id" as varchar) as "meter_id",

        "$Table"."meter" as "meter",

        cast("$Table"."zone_key" as varchar) as "zone_key",

        "$Table"."zone" as "zone",

        cast("$Table"."facility_key" as varchar) as "facility_key",

        "$Table"."facility" as "facility",

        "$Table"."active" as "active",

        "$Table"."online" as "online",

        "$Table"."first_seen" as "first_seen",

        "$Table"."latest_reading_timestamp" as "latest_reading_timestamp",

        "$Table"."status_reference_timestamp" as "status_reference_timestamp",

        "$Table"."minutes_since_latest_reading" as "minutes_since_latest_reading",

        "$Table"."expected_reading_count" as "expected_reading_count",

        "$Table"."actual_reading_count" as "actual_reading_count",

        "$Table"."data_completeness_percent" as "data_completeness_percent",

        "$Table"."meter_status" as "meter_status"

    from "gold"."meter_status" "$Table"

    limit 1000
