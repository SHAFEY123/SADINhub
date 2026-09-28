"""Task 0B driver — build daily_consumption_profile_v2.csv from the Task 0A interval output.

Reads the Task 0A parquet only. No database connection is opened: Task 0B's lineage runs
through the replay, not through Gold.

Usage:
    python src/labels/run_daily_profile.py [--replay outputs/task0a_<ts>/replay_intervals_v2.parquet]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd
import pyarrow.parquet as pq

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from common.io import ML_WORK, new_run_dir, write_run_metadata  # noqa: E402
from labels.daily_profile import build_meter_daily_profile  # noqa: E402

EXPECTED = {
    "replay_interval_rows": 4_260_849,
    "total_kwh": 2_020_697.5,
    "calendar_meter_days": 16_704,
    "meter_days_with_readings": 14_753,
    "inserted_missing_meter_days": 1_951,
    "boundary_meter_days": 58,
    "long_gap_touched_meter_days": 2_421,
    "meter_days_passing_screen": 14_228,
    "null_consumption_interval_rows": 57,
}


def _latest_replay() -> Path:
    runs = sorted((ML_WORK / "outputs").glob("task0a_*/replay_intervals_v2.parquet"))
    if not runs:
        raise FileNotFoundError("no Task 0A output found under ML_WORK/outputs/task0a_*/")
    return runs[-1]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--replay", type=Path, default=None)
    args = ap.parse_args(argv)

    replay_path = args.replay or _latest_replay()
    run_dir = new_run_dir("task0b")
    print(f"replay input : {replay_path}")
    print(f"run directory: {run_dir}")

    pf = pq.ParquetFile(replay_path)
    interval_rows = pf.metadata.num_rows

    frames, null_consumption_rows, total_kwh = [], 0, 0.0
    for rg in range(pf.metadata.num_row_groups):
        rows = pf.read_row_group(rg).to_pandas()
        null_consumption_rows += int(rows["validated_kwh_consumption"].isna().sum())
        total_kwh += float(rows["validated_kwh_consumption"].sum())
        profile = build_meter_daily_profile(rows)
        frames.append(profile)
        print(f"  [{rg + 1:2d}/{pf.metadata.num_row_groups}] "
              f"{profile['meter_label'].iloc[0]:28s} "
              f"days={len(profile):>4}  pass={int(profile['passes_quality_screen'].sum()):>4}")

    daily = pd.concat(frames, ignore_index=True)
    daily = daily.sort_values(["meter_label", "reading_date_saudi"], ignore_index=True)

    csv_path = run_dir / "daily_consumption_profile_v2.csv"
    daily.to_csv(csv_path, index=False)

    actual = {
        "replay_interval_rows": interval_rows,
        "total_kwh": round(total_kwh, 4),
        "calendar_meter_days": int(len(daily)),
        "meter_days_with_readings": int((~daily["is_missing_day"]).sum()),
        "inserted_missing_meter_days": int(daily["is_missing_day"].sum()),
        "boundary_meter_days": int(daily["is_boundary_day"].sum()),
        "long_gap_touched_meter_days": int(daily["is_long_gap_touched"].sum()),
        "meter_days_passing_screen": int(daily["passes_quality_screen"].sum()),
        "null_consumption_interval_rows": null_consumption_rows,
    }
    checks = {
        k: (abs(actual[k] - EXPECTED[k]) < 0.05 if isinstance(EXPECTED[k], float)
            else actual[k] == EXPECTED[k])
        for k in EXPECTED
    }

    # Exclusion categories overlap, so the screen cannot be a subtraction. Quantify it.
    excluded = actual["calendar_meter_days"] - actual["meter_days_passing_screen"]
    category_sum = (actual["inserted_missing_meter_days"]
                    + actual["boundary_meter_days"]
                    + actual["long_gap_touched_meter_days"])

    funnel = {}
    mask = pd.Series(True, index=daily.index)
    for name, cond in [
        ("has_readings", ~daily["is_missing_day"]),
        ("not_boundary_day", ~daily["is_boundary_day"]),
        ("not_long_gap_touched", ~daily["is_long_gap_touched"]),
        ("coverage_95_to_100", (daily["normal_interval_coverage"] >= 0.95)
            & (daily["normal_interval_coverage"] <= 1.00)),
        ("consumption_present_non_negative", ~daily["consumption_is_null"]
            & (daily["validated_kwh_consumption"].fillna(-1) >= 0)),
        ("no_integrity_evidence", ~daily["has_duplicate_timestamp"]
            & ~daily["has_negative_consumption"] & ~daily["has_unrecognised_quality"]
            & ~daily["has_overlapping_normal_interval"]),
    ]:
        mask &= cond
        funnel[name] = int(mask.sum())

    metadata = {
        "task": "0B - daily profile and quality-screen reconstruction",
        "run_directory": str(run_dir),
        "spec": "src/labels/replay_spec.md + addendum Correction 05",
        "inputs": {
            "replay_parquet": str(replay_path),
            "database_opened": False,
            "note": "Task 0B consumes the Task 0A replay output; it does not re-derive "
                    "consumption from gold.energy_consumption_validated.",
        },
        "outputs": {"daily_profile_csv": csv_path.name},
        "reconstruction": {
            "coverage": "clip each interval to the Saudi day, NORMAL_INTERVAL seconds / 86400",
            "coverage_band": [0.95, 1.00],
            "boundary_days": "per meter, min/max reading_date_saudi over ALL replay rows",
            "long_gap_marking": "every Saudi date the gap interval spans, endpoints included",
            "missing_days": "inserted explicitly with null consumption; never zero-filled",
            "screen": "conjunction of six conditions per meter-day",
        },
        "reconciliation": {"expected": EXPECTED, "actual": actual, "checks": checks},
        "integrity_checks": {
            "independently_reconstructed": {
                name: int(daily[col].sum()) for name, col in [
                    ("duplicate_timestamp", "has_duplicate_timestamp"),
                    ("negative_consumption", "has_negative_consumption"),
                    ("unrecognised_interval_quality", "has_unrecognised_quality"),
                    ("overlapping_normal_interval", "has_overlapping_normal_interval"),
                ]
            },
            "not_independently_reconstructable": {
                "inconsistent_normal_interval": (
                    "The replay derives interval_quality itself from gap_minutes, so it "
                    "cannot disagree with itself. A zero here would be a tautology, not "
                    "evidence. Checking this genuinely requires comparing against an "
                    "independently stored interval_quality, which Task 0B does not read."
                ),
                "stored_saudi_date_mismatch": (
                    "The replay derives reading_date_saudi itself from reading_timestamp_utc "
                    "at UTC+3, so it cannot disagree with itself. Verifying a stored-vs-"
                    "derived mismatch requires the stored Gold column, which Task 0B does "
                    "not read."
                ),
            },
            "note": (
                "Pipeline 11.2 lists six integrity checks. Four are independently "
                "reconstructable from the replay output and all return zero. Two are not, "
                "because the replay is the source of the field being checked; they are "
                "recorded as not_independently_reconstructable and must NOT be read as "
                "verified zeros. Both were reported as zero in the original pipeline run "
                "against Gold, where the comparison was meaningful."
            ),
        },
        "screen_funnel_cumulative": funnel,
        "overlap": {
            "meter_days_excluded": excluded,
            "sum_of_exclusion_categories": category_sum,
            "overlap_between_categories": category_sum - excluded,
            "note": "categories overlap (a long gap also produces missing days), which is "
                    "why the screen is evaluated as a conjunction and not a subtraction.",
        },
        "all_checks_passed": all(checks.values()),
    }
    meta_path = write_run_metadata(run_dir, metadata)

    print("\n=== Task 0B reconciliation ===")
    width = max(len(k) for k in EXPECTED)
    for k in EXPECTED:
        print(f"  {'PASS' if checks[k] else 'FAIL'}  {k:<{width}}  "
              f"expected {EXPECTED[k]:>12,}  actual {actual[k]:>12,}")
    print("\nscreen funnel (cumulative):")
    for k, v in funnel.items():
        print(f"  {k:<34s} {v:>7,}")
    print(f"\nexclusion categories sum to {category_sum:,} but only {excluded:,} meter-days "
          f"are excluded -> overlap {category_sum - excluded:,}")
    print(f"\ncsv     : {csv_path}")
    print(f"metadata: {meta_path}")
    return 0 if metadata["all_checks_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
