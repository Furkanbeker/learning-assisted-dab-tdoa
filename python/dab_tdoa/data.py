"""Loading the AI-ready table and the scenario-wise train/val/test split."""

from pathlib import Path

import numpy as np
import pandas as pd

from . import config as cfg


def resolve_data_path(path=None) -> Path:
    """Return the given path, cfg.DATA_PATH or the included dataset."""
    path = path or cfg.DATA_PATH or cfg.DEFAULT_DATA_PATH
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"Dataset not found: {path}")
    return path


def read_table(path: Path) -> pd.DataFrame:
    """Read a CSV file or a folder of CSV parts (one table, original row order)."""
    path = Path(path)
    if path.is_file():
        return pd.read_csv(path)
    parts = sorted(path.glob("*.csv.gz")) or sorted(path.glob("*.csv"))
    if not parts:
        raise FileNotFoundError(f"No CSV parts found in {path}")
    return pd.concat((pd.read_csv(p) for p in parts), ignore_index=True)


def load_and_clean(path: Path) -> pd.DataFrame:
    """Load the table and replace inf/NaN in numeric columns by the median."""
    print(f"\n[LOAD] {path}")
    df = read_table(path)
    print(f"  Shape   : {df.shape}")

    num_cols = df.select_dtypes(include=[np.number]).columns.tolist()
    df[num_cols] = df[num_cols].replace([np.inf, -np.inf], np.nan)
    nan_count = int(df[num_cols].isna().sum().sum())
    if nan_count > 0:
        print(f"  [WARN] {nan_count} NaN values, filled with the column median.")
        for c in num_cols:
            if df[c].isna().any():
                med = df[c].median()
                df[c] = df[c].fillna(med if np.isfinite(med) else 0.0)

    return df


def make_split(df: pd.DataFrame):
    """Scenario-wise split: the MATLAB 'split' column, else a random 70/15/15 split."""
    if cfg.USE_EXISTING_SPLIT and "split" in df.columns:
        s = df["split"].astype(str).str.lower().str.strip()
        tr = df[s == "train"].copy()
        va = df[(s == "val") | (s == "validation")].copy()
        te = df[s == "test"].copy()
        if len(tr) > 0 and len(va) > 0 and len(te) > 0:
            print(f"  Existing split: train={len(tr)} val={len(va)} test={len(te)}")
            return tr, va, te

    scenarios = np.array(sorted(df["scenario_id"].unique()))
    rng = np.random.default_rng(cfg.RANDOM_SEED)
    rng.shuffle(scenarios)
    n = len(scenarios)
    n_tr = int(round(0.70 * n))
    n_va = int(round(0.15 * n))
    tr_sc = set(scenarios[:n_tr])
    va_sc = set(scenarios[n_tr:n_tr + n_va])
    te_sc = set(scenarios[n_tr + n_va:])
    tr = df[df["scenario_id"].isin(tr_sc)].copy()
    va = df[df["scenario_id"].isin(va_sc)].copy()
    te = df[df["scenario_id"].isin(te_sc)].copy()
    print(f"  Random split: train={len(tr)} val={len(va)} test={len(te)}")
    return tr, va, te
