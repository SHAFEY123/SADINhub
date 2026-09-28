"""Model 1 configuration loading. Every threshold comes from config/model1_config.yaml.

No detector in this package hard-codes a threshold. Anything tunable is in the YAML so a
change is visible in a diff and recorded in run metadata.
"""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

import yaml

ML_WORK = Path(__file__).resolve().parent.parent.parent
CONFIG_PATH = ML_WORK / "config" / "model1_config.yaml"

# The production severity ladder. `Anomaly` is recognised by silver.status_rank() but is
# emitted by no v2 classifier, so Model 1 occupies that reserved rank rather than inventing
# a parallel scale. (Decision 5.)
SEVERITY_LADDER = (
    "Acceptable",
    "Review Required",
    "Anomaly",
    "Problematic",
    "Critical",
    "Invalid",
)
SEVERITY_RANK = {name: i for i, name in enumerate(SEVERITY_LADDER)}


@lru_cache(maxsize=1)
def load_config(path: str | None = None) -> dict:
    cfg_path = Path(path) if path else CONFIG_PATH
    if not cfg_path.exists():
        raise FileNotFoundError(f"Model 1 config not found: {cfg_path}")
    cfg = yaml.safe_load(cfg_path.read_text(encoding="utf-8"))
    _validate(cfg)
    return cfg


def _validate(cfg: dict) -> None:
    """Fail loudly at load time rather than silently mis-detecting later."""
    required = ("scope", "commissioning", "episodes", "severity", "t1_polarity",
                "t2_current_power", "t3_power_factor", "t4_change", "t5_register",
                "acceptance_set", "reconciliation")
    missing = [k for k in required if k not in cfg]
    if missing:
        raise ValueError(f"model1_config.yaml is missing sections: {missing}")

    cap = cfg["commissioning"]["severity_cap"]
    if cap not in SEVERITY_RANK:
        raise ValueError(f"commissioning.severity_cap {cap!r} is not on the severity ladder")

    trigger = cfg["t5_register"]["trigger"]
    if trigger not in ("either", "legacy_amps", "normalized"):
        raise ValueError(f"t5_register.trigger {trigger!r} is not a recognised trigger")

    gate = cfg["t3_power_factor"]["min_load_pct_cb"]
    if not 0 < gate < 100:
        raise ValueError(f"t3_power_factor.min_load_pct_cb {gate} is not a sane percentage")


def config_fingerprint(cfg: dict) -> dict:
    """The subset of configuration that changes what a detector does, for run metadata."""
    return {
        "commissioning_boundary": cfg["commissioning"]["assumed_boundary_date"],
        "commissioning_status": cfg["commissioning"]["status"],
        "episode_merge_gap_minutes": cfg["episodes"]["merge_gap_minutes"],
        "t3_min_load_pct_cb": cfg["t3_power_factor"]["min_load_pct_cb"],
        "t3_cusum": {k: cfg["t3_power_factor"][k]
                     for k in ("cusum_target", "cusum_k_sigma", "cusum_h_sigma")},
        "t4_ewma": {k: cfg["t4_change"][k]
                    for k in ("ewma_lambda", "ewma_k", "baseline_window_days",
                              "min_baseline_days", "baseline_gap_days")},
        "t4_min_readings_per_day": cfg["t4_change"]["min_readings_per_day"],
        "t5": {k: cfg["t5_register"][k] for k in ("min_readings_full_day", "min_amps_a",
                                                  "min_load_pct_cb", "trigger")},
    }
