"""
Paper-style figures: GN vs. LC-CT-EKF vs. B3-Ensemble (test set).

Run after run_ai_pipeline.py. Reads b3_pred_test.npy from the output folder
and writes PNG + PDF figures (no titles) and a metrics table to
<out>/paper_figures/.

Usage:
  python make_paper_figures.py
  python make_paper_figures.py --data path/to/ai_ready.csv --out path/to/output
"""

import argparse
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from dab_tdoa import config as cfg
from dab_tdoa.data import load_and_clean, make_split, resolve_data_path
from dab_tdoa.features import build_features
from dab_tdoa.utils import compute_metrics, ensure_dir, pos_error

METHOD_STYLES = {
    "GN": ("-", "tab:blue"),
    "LC-CT-EKF": ("--", "tab:orange"),
    "B3-Ensemble": ("-.", "tab:green"),
}

plt.rcParams.update({
    "figure.dpi": 160,
    "savefig.dpi": 600,
    "font.family": "serif",
    "font.serif": ["Times New Roman", "DejaVu Serif", "Times"],
    "mathtext.fontset": "dejavuserif",
    "axes.labelsize": 11,
    "xtick.labelsize": 10,
    "ytick.labelsize": 10,
    "legend.fontsize": 9,
    "axes.linewidth": 0.9,
    "grid.linewidth": 0.45,
    "lines.linewidth": 1.8,
    "pdf.fonttype": 42,
    "ps.fonttype": 42,
})


def _legend(ax, **kw):
    ax.legend(frameon=True, fancybox=False, edgecolor="black", **kw)


def save_figure(fig, fig_dir, name):
    for ext in ("png", "pdf"):
        fig.savefig(fig_dir / f"{name}.{ext}", bbox_inches="tight", pad_inches=0.03)
    plt.close(fig)
    print(f"[SAVED] {name}.png / .pdf")


def plot_cdf(errors, fig_dir):
    fig, ax = plt.subplots(figsize=(3.55, 2.55))
    for name, err in errors.items():
        e = np.sort(np.asarray(err, float))
        y = np.arange(1, len(e) + 1) / len(e)
        ls, color = METHOD_STYLES[name]
        ax.plot(e, y, linestyle=ls, color=color, linewidth=1.9, label=name)
    ax.set_xlabel("Position error (m)")
    ax.set_ylabel("CDF")
    ax.set_xlim(left=0)
    ax.set_ylim(0, 1.01)
    ax.grid(True, alpha=0.28)
    _legend(ax, loc="lower right")
    fig.tight_layout()
    save_figure(fig, fig_dir, "fig_error_cdf")


def plot_ccdf(errors, fig_dir):
    fig, ax = plt.subplots(figsize=(3.55, 2.55))
    for name, err in errors.items():
        e = np.sort(np.asarray(err, float))
        ccdf = np.maximum(1.0 - np.arange(1, len(e) + 1) / len(e), 1.0 / len(e))
        ls, color = METHOD_STYLES[name]
        ax.semilogy(e, ccdf, linestyle=ls, color=color, linewidth=1.9, label=name)
    ax.set_xlabel("Position error (m)")
    ax.set_ylabel("CCDF")
    ax.set_xlim(left=0)
    ax.grid(True, which="both", alpha=0.28)
    _legend(ax, loc="upper right")
    fig.tight_layout()
    save_figure(fig, fig_dir, "fig_error_ccdf")


def plot_histogram(errors, fig_dir, xmax=50.0, bin_width=2.5):
    """Error density over 0-xmax m; the full tail is reported in the tables."""
    fig, ax = plt.subplots(figsize=(3.55, 2.55))
    bins = np.arange(0.0, xmax + bin_width, bin_width)
    for name, err in errors.items():
        e = np.asarray(err, float)
        e = e[np.isfinite(e)]
        ax.hist(e[(e >= 0) & (e <= xmax)], bins=bins, density=True, alpha=0.45,
                histtype="bar", edgecolor="black", linewidth=0.35,
                color=METHOD_STYLES[name][1], label=name)
    ax.set_xlabel("Position error (m)")
    ax.set_ylabel("Density")
    ax.set_xlim(0, xmax)
    ax.grid(True, axis="y", alpha=0.28)
    _legend(ax)
    fig.tight_layout()
    save_figure(fig, fig_dir, "fig_error_density")


def plot_metric_bars(errors, fig_dir):
    names = list(errors.keys())
    x = np.arange(len(names))
    width = 0.36
    fig, ax = plt.subplots(figsize=(3.55, 2.55))
    ax.bar(x - width / 2, [np.mean(errors[n]) for n in names], width, label="Mean")
    ax.bar(x + width / 2, [np.percentile(errors[n], 95) for n in names], width,
           label="95th percentile")
    ax.set_ylabel("Position error (m)")
    ax.set_xticks(x)
    ax.set_xticklabels(names, rotation=20, ha="right")
    ax.grid(True, axis="y", alpha=0.28)
    _legend(ax)
    fig.tight_layout()
    save_figure(fig, fig_dir, "fig_error_mean_p95")


def plot_spatial_error(true_xy, pred_xy, fig_dir):
    """True UAV positions colored by the B3-Ensemble position error."""
    err = pos_error(true_xy, pred_xy)
    fig, ax = plt.subplots(figsize=(3.25, 3.0))
    sc = ax.scatter(true_xy[:, 0], true_xy[:, 1], c=err, s=6, alpha=0.80,
                    linewidths=0, rasterized=True)
    cbar = fig.colorbar(sc, ax=ax, fraction=0.046, pad=0.04)
    cbar.set_label("Position error (m)")
    ax.set_xlabel("x-position (m)")
    ax.set_ylabel("y-position (m)")
    ax.set_aspect("equal", adjustable="box")
    ax.grid(True, alpha=0.25)
    fig.tight_layout()
    save_figure(fig, fig_dir, "fig_b3_spatial_error")


def plot_motionwise(errors, te, fig_dir):
    if "motion_type" not in te.columns:
        print("[SKIP] motion_type column not found.")
        return
    motions = sorted(te["motion_type"].astype(str).dropna().unique())
    names = list(errors.keys())
    x = np.arange(len(motions))
    width = 0.78 / max(len(names), 1)
    fig, ax = plt.subplots(figsize=(4.9, 2.75))
    for i, name in enumerate(names):
        vals = [float(np.mean(np.asarray(errors[name])[te["motion_type"].astype(str).values == m]))
                for m in motions]
        ax.bar(x - 0.39 + width / 2 + i * width, vals, width,
               color=METHOD_STYLES[name][1], label=name)
    ax.set_ylabel("Mean position error (m)")
    ax.set_xlabel("Motion type")
    ax.set_xticks(x)
    ax.set_xticklabels(motions, rotation=20, ha="right")
    ax.grid(True, axis="y", alpha=0.28)
    _legend(ax, ncol=1)
    fig.tight_layout()
    save_figure(fig, fig_dir, "fig_error_by_motion")


def main(data_path: Path = None, out_dir: Path = None):
    data_path = resolve_data_path(data_path)
    out_dir = Path(out_dir) if out_dir else cfg.OUT_DIR
    fig_dir = out_dir / "paper_figures"
    ensure_dir(fig_dir)

    df = build_features(load_and_clean(data_path))
    _, _, te = make_split(df)
    true_te = te[["uav_rel_x", "uav_rel_y"]].values.astype(float)

    # B3-Ensemble is the method fixed on the validation set
    b3_path = out_dir / "b3_pred_test.npy"
    if not b3_path.exists():
        raise FileNotFoundError(f"{b3_path} not found. Run run_ai_pipeline.py first.")
    b3_pred = np.load(b3_path)
    if b3_pred.shape != true_te.shape:
        raise ValueError(f"B3 prediction shape {b3_pred.shape}, expected {true_te.shape}")

    errors = {"GN": pos_error(true_te, te[["gn_est_rel_x", "gn_est_rel_y"]].values)}
    if all(c in te.columns for c in ["ctekf_est_rel_x", "ctekf_est_rel_y"]):
        errors["LC-CT-EKF"] = pos_error(true_te, te[["ctekf_est_rel_x", "ctekf_est_rel_y"]].values)
    errors["B3-Ensemble"] = pos_error(true_te, b3_pred)

    metrics = pd.DataFrame([compute_metrics(n, e) for n, e in errors.items()])
    metrics = metrics.rename(columns={"model": "method"})
    metrics.to_csv(fig_dir / "metrics_gn_ctekf_b3.csv", index=False)
    print(metrics.to_string(index=False))

    plot_cdf(errors, fig_dir)
    plot_ccdf(errors, fig_dir)
    plot_histogram(errors, fig_dir)
    plot_metric_bars(errors, fig_dir)
    plot_spatial_error(true_te, b3_pred, fig_dir)
    plot_motionwise(errors, te, fig_dir)
    print(f"\nFigures written to: {fig_dir}")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="GN / LC-CT-EKF / B3-Ensemble figures")
    p.add_argument("--data", type=Path, default=None,
                   help="AI-ready CSV or folder of CSV parts")
    p.add_argument("--out", type=Path, default=None,
                   help=f"output folder of run_ai_pipeline.py (default: {cfg.OUT_DIR})")
    args = p.parse_args()
    main(args.data, args.out)
