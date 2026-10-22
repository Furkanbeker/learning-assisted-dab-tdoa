"""Summary tables, per-group analysis, scenario-level bootstrap and plots."""

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from . import config as cfg
from .utils import compute_metrics, pos_error


def build_summary_table(errors_dict: dict) -> pd.DataFrame:
    """Test metrics in the fixed method order (not used for selection)."""
    return pd.DataFrame([compute_metrics(n, e) for n, e in errors_dict.items()])


def _group_rows(te, errors_dict, group, column, labels):
    rows = []
    for label in labels:
        mask = te[column].astype(str).str.lower() == label
        if mask.sum() == 0:
            continue
        r = {"group": group, "label": label, "n": int(mask.sum())}
        for mname, err in errors_dict.items():
            e_sub = err[mask]
            r[f"{mname}_mean_m"] = float(np.mean(e_sub))
            r[f"{mname}_p95_m"] = float(np.percentile(e_sub, 95))
        rows.append(r)
    return rows


def detailed_analysis(te, errors_dict, out_dir):
    """Mean and P95 error per motion type, geometry class and observation quality."""
    print("\n" + "=" * 68)
    print("DETAILED ANALYSIS")
    print("=" * 68)
    rows = []

    if "motion_type" in te.columns:
        for mt in sorted(te["motion_type"].dropna().unique()):
            mask = te["motion_type"].astype(str) == str(mt)
            r = {"group": "motion", "label": str(mt), "n": int(mask.sum())}
            for mname, err in errors_dict.items():
                e_sub = err[mask]
                r[f"{mname}_mean_m"] = float(np.mean(e_sub))
                r[f"{mname}_p95_m"] = float(np.percentile(e_sub, 95))
            rows.append(r)

    if "geometry_class_est" in te.columns:
        rows += _group_rows(te, errors_dict, "geometry",
                            "geometry_class_est", ["good", "medium", "bad"])

    if "observation_quality_class" in te.columns:
        rows += _group_rows(te, errors_dict, "obs_quality",
                            "observation_quality_class", ["good", "medium", "bad"])

    df_detail = pd.DataFrame(rows)
    df_detail.to_csv(out_dir / "detailed_analysis.csv", index=False)
    print(df_detail.to_string(index=False))
    return df_detail


def scenario_bootstrap_ci(te, errors_dict, out_dir,
                          n_boot=cfg.BOOTSTRAP_N,
                          seed=cfg.BOOTSTRAP_SEED,
                          baseline_key="GN_baseline"):
    """95% CIs of the mean error and of the gain vs. GN.

    Paired bootstrap over test scenarios (each scenario is one resampling
    unit). Reporting only; not used for any selection.
    """
    if "scenario_id" not in te.columns:
        print("  [BOOTSTRAP SKIP] scenario_id is missing.")
        return pd.DataFrame()

    method_names = list(errors_dict.keys())
    n_rows = len(te)
    for name, err in errors_dict.items():
        if len(err) != n_rows:
            raise ValueError(f"Bootstrap length mismatch for {name}: "
                             f"{len(err)} vs {n_rows}")

    scenario_ids = np.asarray(sorted(te["scenario_id"].unique()))
    n_sc = len(scenario_ids)
    if n_sc < 2:
        print("  [BOOTSTRAP SKIP] fewer than two test scenarios.")
        return pd.DataFrame()

    # Per-scenario mean error of every method
    sid = te["scenario_id"].to_numpy()
    sc_means = np.zeros((n_sc, len(method_names)), dtype=float)
    for i, sc in enumerate(scenario_ids):
        mask = sid == sc
        for j, name in enumerate(method_names):
            sc_means[i, j] = float(np.mean(np.asarray(errors_dict[name])[mask]))

    rng = np.random.default_rng(seed)
    boot_means = np.empty((n_boot, len(method_names)), dtype=float)
    for b in range(n_boot):
        sample_idx = rng.integers(0, n_sc, size=n_sc)
        boot_means[b] = sc_means[sample_idx].mean(axis=0)

    base_idx = method_names.index(baseline_key) if baseline_key in method_names else None
    rows = []
    for j, name in enumerate(method_names):
        vals = boot_means[:, j]
        row = {
            "model": name,
            "n_test_scenarios": int(n_sc),
            "bootstrap_replicates": int(n_boot),
            "mean_m": float(sc_means[:, j].mean()),
            "ci95_low_m": float(np.percentile(vals, 2.5)),
            "ci95_high_m": float(np.percentile(vals, 97.5)),
        }

        if base_idx is not None:
            base_mean = sc_means[:, base_idx].mean()
            base_vals = boot_means[:, base_idx]
            diff_vals = base_vals - vals
            gain_vals = 100.0 * diff_vals / np.maximum(base_vals, 1e-12)
            row.update({
                "mean_gain_vs_gn_m": float(base_mean - sc_means[:, j].mean()),
                "gain_vs_gn_ci95_low_m": float(np.percentile(diff_vals, 2.5)),
                "gain_vs_gn_ci95_high_m": float(np.percentile(diff_vals, 97.5)),
                "mean_gain_vs_gn_percent": float(
                    100.0 * (base_mean - sc_means[:, j].mean()) / max(base_mean, 1e-12)),
                "gain_vs_gn_ci95_low_percent": float(np.percentile(gain_vals, 2.5)),
                "gain_vs_gn_ci95_high_percent": float(np.percentile(gain_vals, 97.5)),
            })
        rows.append(row)

    df_boot = pd.DataFrame(rows)
    df_boot.to_csv(out_dir / "scenario_bootstrap_ci.csv", index=False)
    print("\n[SCENARIO-LEVEL PAIRED BOOTSTRAP - TEST SET]")
    print(df_boot.to_string(index=False))
    return df_boot


# -----------------------------------------------------------------------------
# Diagnostic plots
# -----------------------------------------------------------------------------

def plot_cdf(errors_dict: dict, path: Path):
    plt.figure(figsize=(9, 5))
    styles = ["-", "--", "-.", ":", (0, (5, 1)), (0, (3, 1, 1, 1))]
    for i, (name, err) in enumerate(errors_dict.items()):
        e = np.sort(np.asarray(err, float))
        y = np.arange(1, len(e) + 1) / len(e)
        plt.plot(e, y, label=name, linestyle=styles[i % len(styles)], linewidth=1.8)
    plt.xlabel("Position error [m]", fontsize=12)
    plt.ylabel("CDF", fontsize=12)
    plt.title("Test-set position error CDF", fontsize=13)
    plt.legend(fontsize=9, loc="lower right")
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(path, dpi=220)
    plt.close()
    print(f"  [PLOT] {path.name}")


def plot_histogram(errors_dict: dict, path: Path):
    plt.figure(figsize=(9, 5))
    for name, err in errors_dict.items():
        plt.hist(np.asarray(err, float), bins=60, alpha=0.40, label=name, density=True)
    plt.xlabel("Position error [m]", fontsize=12)
    plt.ylabel("Density", fontsize=12)
    plt.title("Test-set position error histogram", fontsize=13)
    plt.legend(fontsize=9)
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(path, dpi=220)
    plt.close()
    print(f"  [PLOT] {path.name}")


def plot_scatter(true_xy, pred_xy, name, path):
    """True UAV positions colored by the position error."""
    err = pos_error(true_xy, pred_xy)
    plt.figure(figsize=(7, 6))
    sc = plt.scatter(true_xy[:, 0], true_xy[:, 1], c=err, cmap="hot_r", s=8, alpha=0.7)
    plt.colorbar(sc, label="Error [m]")
    plt.xlabel("X [m]")
    plt.ylabel("Y [m]")
    plt.title(f"{name} - test error map")
    plt.tight_layout()
    plt.savefig(path, dpi=200)
    plt.close()
    print(f"  [PLOT] {path.name}")
