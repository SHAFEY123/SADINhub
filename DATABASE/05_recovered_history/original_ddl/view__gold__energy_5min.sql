-- Recovered from PostgreSQL server log postgresql-2026-08-09_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

CREATE OR REPLACE VIEW gold.energy_5min AS
    SELECT * FROM silver.agg_energy_5min;
