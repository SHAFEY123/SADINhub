"""Model 3 configuration loading. Every threshold comes from config/model3_config.yaml."""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

import yaml

ML_WORK = Path(__file__).resolve().parent.parent.parent
CONFIG_PATH = ML_WORK / "config" / "model3_config.yaml"


@lru_cache(maxsize=1)
def load_config(path: str | None = None) -> dict:
    cfg_path = Path(path) if path else CONFIG_PATH
    if not cfg_path.exists():
        raise FileNotFoundError(f"Model 3 config not found: {cfg_path}")
    cfg = yaml.safe_load(cfg_path.read_text(encoding="utf-8"))
    _validate(cfg)
    return cfg


def _validate(cfg: dict) -> None:
    required = ("scope", "saudi", "features", "isolation_forest", "ranking", "crosscheck")
    missing = [k for k in required if k not in cfg]
    if missing:
        raise ValueError(f"model3_config.yaml is missing sections: {missing}")

    f = cfg["features"]
    overlap = set(f["bounded_rate_features"]) & set(f["unbounded_features"])
    if overlap:
        raise ValueError(f"features cannot be both bounded and unbounded: {sorted(overlap)}")
    # Every Tier 1 feature must be declared either bounded or unbounded, so a new feature
    # cannot slip in without a range contract.
    declared = set(f["bounded_rate_features"]) | set(f["unbounded_features"])
    undeclared = [c for c in f["tier1"] if c not in declared]
    if undeclared:
        raise ValueError(f"Tier 1 features with no declared range contract: {undeclared}")

    p = cfg["isolation_forest"]
    if p["min_train_dates"] > p["train_window_days"]:
        raise ValueError("min_train_dates cannot exceed train_window_days")
    if p["contamination"] != "auto":
        raise ValueError(
            "contamination must stay 'auto': Model 3 never calls predict(), and a numeric "
            "value invites reading it as a fault-prevalence estimate")

    r = cfg["ranking"]
    if r["primary"] != "window_anomaly_pct":
        raise ValueError("window_anomaly_pct must remain the primary ranking score")
    if r["tie_break"] != "window_anomaly_z":
        raise ValueError("window_anomaly_z is the secondary tie-break only")

    c = cfg["crosscheck"]
    if not c["explains_requires"]["same_meter_same_day"]:
        raise ValueError(
            "'explained' is judged per meter-day, never facility-wide")
    if c["explains_requires"]["event_class"] != "ELECTRICAL_FAULT":
        raise ValueError(
            "only an ELECTRICAL_FAULT event can explain a Model 3 item")
    if c["explains_requires"]["commissioning"] is not False:
        raise ValueError("a commissioning artifact is not an explanation")


def config_fingerprint(cfg: dict) -> dict:
    """The subset of configuration that changes what the model does."""
    return {
        "pf_gate_pct_cb": cfg["features"]["pf_gate_pct_cb"],
        "pf_critical_below": cfg["features"]["pf_critical_below"],
        "dev28": {k: cfg["features"][k]
                  for k in ("dev28_window_days", "dev28_min_periods")},
        "isolation_forest": dict(cfg["isolation_forest"]),
        "ranking": dict(cfg["ranking"]),
        "crosscheck": {k: cfg["crosscheck"][k]
                       for k in ("explains_requires", "context_only_classes",
                                 "families", "n_permutations", "permutation_seed")},
        "tier1_features": cfg["features"]["tier1"],
        "tier2_features": cfg["features"]["tier2"],
    }
