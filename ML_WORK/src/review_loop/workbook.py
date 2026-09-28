"""Task 4 — workbook construction, blinding and cell protection.

Two sheets with different blinding regimes:

  findings    every row is flagged by definition, so there is no flag status to conceal.
              What is concealed is Model 1's VERDICT: severity, magnitude band and the
              corroboration judgement.
  meter_days  flagged and unflagged rows are mixed and must be indistinguishable, so flag
              status, detector family, severity, Model 3 score and rank, stratum and any
              model-written description are all withheld.

Evidence on the meter-day sheet is computed uniformly for every observed meter-day from the
Model 3 feature table. It CANNOT come from Model 1 event records: those exist only for
flagged rows, and their presence would itself be the tell.
"""
from __future__ import annotations

from pathlib import Path

import pandas as pd

# ---- columns a reviewer sees. Nothing here reveals what a model concluded.
FINDING_VISIBLE = [
    "review_id", "reviewer_id", "meter", "phase", "first_date", "last_date",
    "n_days_spanned", "n_episodes", "observation",
    "evidence_metric", "evidence_value", "evidence_unit",
    "concurrent_classifier_status",
]
FINDING_LABELS = ["confirmed_fault", "fault_type", "notes", "reviewed_at"]

METER_DAY_VISIBLE = [
    "review_id", "reviewer_id", "meter", "date",
    "readings_reported", "coverage_ratio", "mean_load_pct_cb",
    "negative_total_power_rate", "negative_phase_power_rate",
    "current_without_power_rate", "power_without_current_rate",
    "pf_critical_rate_phase_1", "pf_critical_rate_phase_2", "pf_critical_rate_phase_3",
    "pf_load_gate_open_rate_1", "pf_load_gate_open_rate_2", "pf_load_gate_open_rate_3",
    "major_issue_rate", "major_problem_rate",
    "voltage_not_acceptable_rate", "frequency_not_acceptable_rate",
]
METER_DAY_LABELS = ["engineering_abnormality", "electrical_fault", "abnormality_type",
                    "notes", "reviewed_at"]

# Anything matching these must never reach a reviewer sheet.
FORBIDDEN_SUBSTRINGS = ("severity", "window_anomaly", "daily_rank", "raw_score",
                        "stratum", "m1_", "family", "detector", "description",
                        "inclusion_probability", "design_weight", "cell",
                        "magnitude", "corroboration", "commissioning", "explains")


def assert_blinded(df: pd.DataFrame, allow: tuple[str, ...] = ()) -> None:
    """Fail loudly if a sheet carries anything that reveals a model's conclusion."""
    leaked = [c for c in df.columns
              if c not in allow
              and any(bad in c.lower() for bad in FORBIDDEN_SUBSTRINGS)]
    if leaked:
        raise RuntimeError(f"blinding violation - these columns reveal the model: {leaked}")


def shuffle(df: pd.DataFrame, seed: int) -> pd.DataFrame:
    """Randomise row order so the sheet is not sorted by anything being measured."""
    return df.sample(frac=1.0, random_state=seed).reset_index(drop=True)


def write_workbook(path: Path, sheets: dict[str, pd.DataFrame],
                   editable: dict[str, list[str]], validation: dict[str, dict],
                   protect: bool = True) -> Path:
    """Write an .xlsx with every cell locked except the label columns.

    `reviewer_id` is pre-populated and stays LOCKED: if reviewers could type it, the 10%
    double-labelled overlap sample could be mis-attributed and the agreement estimate would
    be meaningless.
    """
    from openpyxl.styles import Alignment, Font, PatternFill, Protection
    from openpyxl.utils import get_column_letter
    from openpyxl.worksheet.datavalidation import DataValidation

    with pd.ExcelWriter(path, engine="openpyxl") as writer:
        for name, df in sheets.items():
            df.to_excel(writer, sheet_name=name, index=False)
            ws = writer.sheets[name]
            n_rows, n_cols = len(df), len(df.columns)
            editable_cols = set(editable.get(name, []))

            header_fill = PatternFill("solid", fgColor="1F3864")
            label_fill = PatternFill("solid", fgColor="FFF2CC")
            for j, col in enumerate(df.columns, start=1):
                cell = ws.cell(row=1, column=j)
                cell.font = Font(bold=True, color="FFFFFF")
                cell.fill = header_fill
                cell.alignment = Alignment(wrap_text=True, vertical="center")
                width = 34 if col in ("observation", "notes") else max(12, min(len(col) + 4, 26))
                ws.column_dimensions[get_column_letter(j)].width = width

            for j, col in enumerate(df.columns, start=1):
                unlocked = col in editable_cols
                for i in range(2, n_rows + 2):
                    c = ws.cell(row=i, column=j)
                    c.protection = Protection(locked=not unlocked)
                    if unlocked:
                        c.fill = label_fill

            for col, values in validation.get(name, {}).items():
                if col not in df.columns:
                    continue
                j = list(df.columns).index(col) + 1
                letter = get_column_letter(j)
                dv = DataValidation(type="list",
                                    formula1='"' + ",".join(values) + '"',
                                    allow_blank=True, showDropDown=False)
                dv.error = "Choose one of the listed values."
                ws.add_data_validation(dv)
                dv.add(f"{letter}2:{letter}{n_rows + 1}")

            ws.freeze_panes = "A2"
            ws.auto_filter.ref = f"A1:{get_column_letter(n_cols)}{n_rows + 1}"
            if protect:
                # No password: this guards against accidental edits, it is not a secret,
                # and a password would only obstruct the reviewer.
                ws.protection.sheet = True
                ws.protection.formatCells = False
                ws.protection.selectLockedCells = True
                ws.protection.selectUnlockedCells = True
    return path
