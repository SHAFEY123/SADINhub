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

        "$Table"."expected_reading_count" as "expected_reading_count",

        "$Table"."actual_reading_count" as "actual_reading_count",

        "$Table"."missing_reading_count" as "missing_reading_count",

        "$Table"."duplicate_measurement_count" as "duplicate_measurement_count",

        "$Table"."average_populated_measurement_count" as "average_populated_measurement_count",

        "$Table"."populated_measurement_percent" as "populated_measurement_percent",

        "$Table"."data_completeness_percent" as "data_completeness_percent",

        "$Table"."measurement_coverage_status" as "measurement_coverage_status",

        "$Table"."quality_status" as "quality_status"

    from "gold"."data_quality" "$Table"

    limit 100
