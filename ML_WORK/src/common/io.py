"""Versioned output writing and run metadata.

Every run writes into ML_WORK/outputs/run_<UTC timestamp>/ and finishes with a
run_metadata.json recording what was read, what was produced and how it reconciled.
Nothing is ever written outside ML_WORK/, and no credential is recorded.
"""
from __future__ import annotations

import json
import platform
from datetime import datetime, timezone
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

ML_WORK = Path(__file__).resolve().parent.parent.parent
OUTPUTS = ML_WORK / "outputs"


def new_run_dir(prefix: str = "run") -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = OUTPUTS / f"{prefix}_{stamp}"
    path.mkdir(parents=True, exist_ok=True)
    return path


class ParquetAppender:
    """Incremental parquet writer, so 4.26M rows never sit in memory at once."""

    def __init__(self, path: Path):
        self.path = Path(path)
        self._writer: pq.ParquetWriter | None = None
        self._schema: pa.Schema | None = None
        self.rows = 0

    def append(self, df) -> None:
        table = pa.Table.from_pandas(df, preserve_index=False)
        if self._writer is None:
            self._schema = table.schema
            self._writer = pq.ParquetWriter(self.path, self._schema)
        elif not table.schema.equals(self._schema):
            # Later batches must land in the first batch's schema; a per-meter dtype drift
            # (e.g. an all-null column inferring differently) would otherwise fail the write.
            table = table.cast(self._schema)
        self._writer.write_table(table)
        self.rows += len(df)

    def close(self) -> None:
        if self._writer is not None:
            self._writer.close()
            self._writer = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def environment_facts() -> dict:
    import numpy, pandas, psycopg  # noqa: E401
    return {
        "python": platform.python_version(),
        "platform": platform.platform(),
        "pandas": pandas.__version__,
        "numpy": numpy.__version__,
        "psycopg": psycopg.__version__,
        "pyarrow": pa.__version__,
    }


def write_run_metadata(run_dir: Path, payload: dict,
                       filename: str = "run_metadata.json") -> Path:
    payload = dict(payload)
    payload.setdefault("generated_at_utc", datetime.now(timezone.utc).isoformat())
    payload.setdefault("environment", environment_facts())

    # Defensive: never let a credential reach disk. No legitimate metadata field is named
    # after a password, so the bare substring is a safe thing to refuse on.
    blob = json.dumps(payload, indent=2, default=str)
    if "password" in blob.lower():
        raise RuntimeError(
            "run_metadata would contain the substring 'password' — refusing to write"
        )

    path = Path(run_dir) / filename
    path.write_text(blob, encoding="utf-8")
    return path
