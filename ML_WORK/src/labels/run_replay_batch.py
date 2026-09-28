"""Task 0A batch driver.

Replays the §6.7 rule for all 29 in-scope meters from the raw register, then — and only
then — opens gold.energy_consumption_validated to compare.

One meter at a time: each is an index-ordered scan on
pk_energy_readings_snapshot(energy_meter_key, reading_timestamp_utc), and results stream to
parquet, so peak memory stays at one meter (~164k rows) rather than 4.26M.

Usage:
    python src/labels/run_replay_batch.py [--limit-meters N] [--no-compare]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from common.io import ParquetAppender, new_run_dir, write_run_metadata  # noqa: E402
from db import connection_facts, readonly_connection  # noqa: E402
from labels.replay import replay_full_history  # noqa: E402
from meters import fetch_meter_readings, load_meter_dim, replay_scope  # noqa: E402

TOLERANCE = 1e-9

GOLD_COMPARE_SQL = """
    SELECT reading_timestamp_utc,
           validated_kwh_consumption,
           interval_quality,
           consumption_cleaning_status,
           gap_minutes
    FROM gold.energy_consumption_validated
    WHERE energy_meter_key = %s
    ORDER BY reading_timestamp_utc
"""

EXPECTED = {
    "rows": 4_260_849,
    "meters": 29,
    "total_kwh": 2_020_697.5,
    "interval_quality": {
        "NORMAL_INTERVAL": 4_259_917,
        "LONG_GAP": 875,
        "FIRST_VALID_READING": 29,
        "IGNORED_READING": 28,
    },
    "cleaning_status": {
        "KEEP": 4_260_821,
        "ISOLATED_LOW_BAD": 22,
        "STARTUP_EXCLUDED": 5,
        "ISOLATED_HIGH_BAD": 1,
    },
    "long_gap_kwh": 354_242.5,
    "normal_interval_kwh": 1_666_455.0,
}


def _fetch_gold(conn, key) -> pd.DataFrame:
    with conn.cursor() as cur:
        cur.execute(GOLD_COMPARE_SQL, (key,))
        rows = cur.fetchall()
    return pd.DataFrame(rows, columns=[
        "reading_timestamp_utc", "validated_kwh_consumption",
        "interval_quality", "consumption_cleaning_status", "gap_minutes",
    ])


def _compare(rep: pd.DataFrame, gold: pd.DataFrame) -> dict:
    """Row-for-row comparison on reading_timestamp_utc."""
    merged = rep.merge(
        gold, on="reading_timestamp_utc", how="outer",
        suffixes=("_replay", "_gold"), indicator=True,
    )
    only_replay = int((merged["_merge"] == "left_only").sum())
    only_gold = int((merged["_merge"] == "right_only").sum())
    both = merged.loc[merged["_merge"] == "both"]

    r_kwh = both["validated_kwh_consumption_replay"].to_numpy(dtype=float)
    g_kwh = both["validated_kwh_consumption_gold"].astype(float).to_numpy()
    both_nan = np.isnan(r_kwh) & np.isnan(g_kwh)
    close = np.isclose(r_kwh, g_kwh, rtol=0.0, atol=TOLERANCE, equal_nan=True)
    exact = (r_kwh == g_kwh) | both_nan

    iq_match = (both["interval_quality_replay"] == both["interval_quality_gold"])
    cs_match = (
        both["consumption_cleaning_status_replay"]
        == both["consumption_cleaning_status_gold"]
    )
    return {
        "rows_compared": int(len(both)),
        "rows_only_in_replay": only_replay,
        "rows_only_in_gold": only_gold,
        "kwh_mismatches": int((~close).sum()),
        "kwh_exact_matches": int(exact.sum()),
        "interval_quality_mismatches": int((~iq_match).sum()),
        "cleaning_status_mismatches": int((~cs_match).sum()),
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit-meters", type=int, default=None)
    ap.add_argument("--no-compare", action="store_true")
    args = ap.parse_args(argv)

    run_dir = new_run_dir("task0a")
    parquet_path = run_dir / "replay_intervals_v2.parquet"
    print(f"run directory: {run_dir}")

    per_meter, totals = [], {
        "rows": 0, "kwh": 0.0, "realtime_differs": 0, "provisional": 0,
    }
    iq_counts: dict[str, int] = {}
    cs_counts: dict[str, int] = {}
    kwh_by_iq: dict[str, float] = {}
    compare_totals = {
        "rows_compared": 0, "rows_only_in_replay": 0, "rows_only_in_gold": 0,
        "kwh_mismatches": 0, "kwh_exact_matches": 0,
        "interval_quality_mismatches": 0, "cleaning_status_mismatches": 0,
    }

    with readonly_connection() as conn:
        facts = connection_facts(conn)
        print(f"read-only: {facts['transaction_read_only']} | "
              f"isolation: {facts['transaction_isolation']}")

        meter_dim = load_meter_dim(conn)
        scope = replay_scope(meter_dim)
        if args.limit_meters:
            scope = scope.head(args.limit_meters)
        print(f"meters in scope: {len(scope)} (of {len(meter_dim)} canonical)")

        with ParquetAppender(parquet_path) as writer:
            for i, row in enumerate(scope.itertuples(index=False), start=1):
                readings = fetch_meter_readings(conn, row.energy_meter_key)
                rep = replay_full_history(
                    readings, row.meter_label, energy_meter_key=str(row.energy_meter_key)
                )

                stats = {
                    "meter_label": row.meter_label,
                    "rows": int(len(rep)),
                    "kwh": float(rep["validated_kwh_consumption"].sum(skipna=True)),
                    "realtime_differs": int(rep["realtime_differs"].sum()),
                    "provisional_at_own_day_close": int(
                        rep["provisional_at_own_day_close"].sum()),
                }

                if not args.no_compare:
                    gold = _fetch_gold(conn, row.energy_meter_key)
                    cmp = _compare(rep, gold)
                    stats.update(cmp)
                    for k in compare_totals:
                        compare_totals[k] += cmp[k]

                for q, c in rep["interval_quality"].value_counts().items():
                    iq_counts[q] = iq_counts.get(q, 0) + int(c)
                for s, c in rep["consumption_cleaning_status"].value_counts().items():
                    cs_counts[s] = cs_counts.get(s, 0) + int(c)
                grouped = rep.groupby("interval_quality")["validated_kwh_consumption"].sum()
                for q, v in grouped.items():
                    kwh_by_iq[q] = kwh_by_iq.get(q, 0.0) + float(v)

                totals["rows"] += stats["rows"]
                totals["kwh"] += stats["kwh"]
                totals["realtime_differs"] += stats["realtime_differs"]
                totals["provisional"] += stats["provisional_at_own_day_close"]

                writer.append(rep)
                per_meter.append(stats)
                print(f"  [{i:2d}/{len(scope)}] {row.meter_label:28s} "
                      f"rows={stats['rows']:>7,} kwh={stats['kwh']:>12,.1f} "
                      f"rt_differs={stats['realtime_differs']}")

    per_meter_df = pd.DataFrame(per_meter)
    per_meter_df.to_csv(run_dir / "replay_reconciliation_by_meter.csv", index=False)

    divergence_pct = 100.0 * totals["realtime_differs"] / max(totals["rows"], 1)
    full_scope = args.limit_meters is None

    checks = {
        "row_count_matches_4260849": totals["rows"] == EXPECTED["rows"] if full_scope else None,
        "meter_count_is_29": len(per_meter) == EXPECTED["meters"] if full_scope else None,
        "total_kwh_matches_2020697_5":
            (abs(totals["kwh"] - EXPECTED["total_kwh"]) < 0.05) if full_scope else None,
        "interval_quality_distribution_matches":
            (iq_counts == EXPECTED["interval_quality"]) if full_scope else None,
        "cleaning_status_distribution_matches":
            (cs_counts == EXPECTED["cleaning_status"]) if full_scope else None,
        "zero_kwh_mismatches_vs_gold": compare_totals["kwh_mismatches"] == 0,
        "zero_interval_quality_mismatches_vs_gold":
            compare_totals["interval_quality_mismatches"] == 0,
        "zero_rows_only_in_gold": compare_totals["rows_only_in_gold"] == 0,
        "zero_rows_only_in_replay": compare_totals["rows_only_in_replay"] == 0,
    }

    metadata = {
        "task": "0A - leakage-safe point-in-time replay",
        "run_directory": str(run_dir),
        "spec": "src/labels/replay_spec.md",
        "inputs": {
            "replay_input": ["gold.energy_raw", "gold.meter"],
            "replay_input_columns": [
                "energy_meter_key", "reading_timestamp_utc",
                "active_energy_cumulative_kwh", "meter_label",
            ],
            "comparison_target": "gold.energy_consumption_validated",
            "comparison_opened_after_replay": True,
            "scope_filter": "meter_label NOT LIKE 'ZN.13-%'",
        },
        "connection": facts,
        "outputs": {
            "intervals_parquet": str(parquet_path.name),
            "reconciliation_by_meter_csv": "replay_reconciliation_by_meter.csv",
        },
        "reconciliation": {
            "rows_emitted": totals["rows"],
            "meters": len(per_meter),
            "total_validated_kwh": round(totals["kwh"], 4),
            "interval_quality_counts": iq_counts,
            "cleaning_status_counts": cs_counts,
            "kwh_by_interval_quality": {k: round(v, 1) for k, v in kwh_by_iq.items()},
            "expected": EXPECTED,
        },
        "comparison_vs_gold": compare_totals,
        "leakage": {
            "rows_where_realtime_differs_from_retrospective": totals["realtime_differs"],
            "pct_rows_replay_differs_from_retrospective": round(divergence_pct, 6),
            "rows_provisional_at_own_day_close": totals["provisional"],
            "pct_provisional_at_own_day_close":
                round(100.0 * totals["provisional"] / max(totals["rows"], 1), 6),
            "note": (
                "realtime_status is the classification available at the close of each "
                "reading's own Saudi day. A row provisional at its own day close is "
                "re-resolved on the next day's pass; it only diverges if the settled "
                "classification differs."
            ),
        },
        "checks": checks,
        "all_checks_passed": all(v for v in checks.values() if v is not None),
        "partial_run": not full_scope,
    }
    meta_path = write_run_metadata(run_dir, metadata)

    print("\n=== Task 0A reconciliation ===")
    print(f"rows emitted        : {totals['rows']:,}")
    print(f"meters              : {len(per_meter)}")
    print(f"total validated kWh : {totals['kwh']:,.4f}")
    print(f"interval_quality    : {iq_counts}")
    print(f"cleaning_status     : {cs_counts}")
    print(f"vs gold             : {compare_totals}")
    print(f"divergence          : {totals['realtime_differs']} rows "
          f"({divergence_pct:.6f}%)")
    print(f"provisional at close: {totals['provisional']:,}")
    for name, ok in checks.items():
        print(f"  {'PASS' if ok else ('SKIP' if ok is None else 'FAIL')}  {name}")
    print(f"\nmetadata: {meta_path}")
    return 0 if metadata["all_checks_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
