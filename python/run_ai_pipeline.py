"""
DAB SoOP TDOA - learning-assisted localization pipeline.

Trains the learning-assisted corrections on the AI-ready dataset and
evaluates all methods on the scenario-disjoint test set:

  GN       multi-start weighted GN (from the dataset)
  CT-EKF   loosely coupled CT-EKF on GN (from the dataset)
  L1       GN position-error correction
  B1       per-link TDOA-error correction + weighted GN
  B2       B1 + tight TDOA CT-EKF, uniform R
  B3       B1 + tight TDOA CT-EKF, learned per-link R-scales (ensemble)

Model families and EKF parameters are selected on the validation set; the
test set is used for reporting only.

Usage:
  python run_ai_pipeline.py                         # dataset in ../dataset_results
  python run_ai_pipeline.py --data path/to/ai_ready.csv --out path/to/output
"""

import argparse
import warnings
from pathlib import Path

import numpy as np
import pandas as pd

from dab_tdoa import config as cfg
from dab_tdoa.analysis import (build_summary_table, detailed_analysis,
                               plot_cdf, plot_histogram, plot_scatter,
                               scenario_bootstrap_ci)
from dab_tdoa.data import load_and_clean, make_split, resolve_data_path
from dab_tdoa.features import TARGET_B1, TARGET_L1, build_features, select_features
from dab_tdoa.levels import run_l1, run_b1, run_b2_b3
from dab_tdoa.utils import compute_metrics, ensure_dir, pos_error, print_metrics, save_json

warnings.filterwarnings("ignore")

REQUIRED_COLUMNS = (["scenario_id", "meas_idx",
                     "gn_est_rel_x", "gn_est_rel_y",
                     "uav_rel_x", "uav_rel_y"]
                    + [f"tx{k}_rel_x" for k in range(1, 5)]
                    + [f"tx{k}_rel_y" for k in range(1, 5)]
                    + [f"est_deltaTau_ch{k}" for k in range(1, 5)])


def parse_args():
    p = argparse.ArgumentParser(description="DAB SoOP TDOA AI pipeline")
    p.add_argument("--data", type=Path, default=None,
                   help="AI-ready CSV or folder of CSV parts "
                        "(default: dataset_results/dab_soop_tdoa_ai_ready_gn_correction)")
    p.add_argument("--out", type=Path, default=None,
                   help=f"output folder (default: {cfg.OUT_DIR})")
    return p.parse_args()


def main(data_path: Path = None, out_dir: Path = None):
    data_path = resolve_data_path(data_path)
    out_dir = Path(out_dir) if out_dir else cfg.OUT_DIR
    cfg.DATA_PATH, cfg.OUT_DIR = data_path, out_dir
    ensure_dir(out_dir)

    print("\n" + "=" * 68)
    print("DAB SoOP TDOA - AI Localization Pipeline")
    print("=" * 68)

    df_raw = load_and_clean(data_path)
    missing = [c for c in REQUIRED_COLUMNS if c not in df_raw.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")

    has_ctekf = all(c in df_raw.columns for c in ["ctekf_est_rel_x", "ctekf_est_rel_y"])
    has_l1_target = all(c in df_raw.columns for c in TARGET_L1)
    has_b1_target = all(c in df_raw.columns for c in TARGET_B1)

    # -- Features and split -------------------------------------------------
    print("\n[FEATURES]")
    df = build_features(df_raw)
    feat_cols = select_features(df)
    print(f"  Number of features: {len(feat_cols)}")
    pd.DataFrame({"feature": feat_cols}).to_csv(out_dir / "feature_list.csv", index=False)

    print("\n[SPLIT]")
    tr, va, te = make_split(df)
    for name, part in (("Train", tr), ("Val", va), ("Test", te)):
        print(f"  {name:5s}: {len(part)} rows | {part['scenario_id'].nunique()} scenarios")

    # -- Baselines ----------------------------------------------------------
    true_te = te[["uav_rel_x", "uav_rel_y"]].values
    err_gn_te = pos_error(true_te, te[["gn_est_rel_x", "gn_est_rel_y"]].values)
    print_metrics(compute_metrics("GN_baseline_test", err_gn_te))
    errors_all = {"GN_baseline": err_gn_te}

    err_ct_te = None
    if has_ctekf:
        err_ct_te = pos_error(true_te, te[["ctekf_est_rel_x", "ctekf_est_rel_y"]].values)
        print_metrics(compute_metrics("CT-EKF_baseline_test", err_ct_te))
        errors_all["CT-EKF_baseline"] = err_ct_te

    # -- L1 -----------------------------------------------------------------
    l1_res = None
    if has_l1_target:
        l1_res, best_l1 = run_l1(tr, va, te, feat_cols, out_dir)
        if l1_res:
            errors_all[f"L1_{best_l1}"] = l1_res[best_l1]["err_test"]
            print_metrics(compute_metrics(f"L1_{best_l1}_test", errors_all[f"L1_{best_l1}"]))
    else:
        print("\n[SKIP] L1: gn_err_x/y not found.")

    # -- B1 -----------------------------------------------------------------
    b1_res = None
    if has_b1_target:
        b1_res, best_b1 = run_b1(tr, va, te, feat_cols, out_dir)
        if b1_res:
            errors_all[f"B1_{best_b1}"] = b1_res[best_b1]["err_test"]
            print_metrics(compute_metrics(f"B1_{best_b1}_test", errors_all[f"B1_{best_b1}"]))
    else:
        print("\n[SKIP] B1: delta_err_ch1-4 not found.")

    # -- B2 and B3 ----------------------------------------------------------
    b2_res = b3_res = None
    if b1_res is not None:
        b2_res, b3_res = run_b2_b3(tr, va, te, feat_cols, b1_res, best_b1, out_dir)
        errors_all["B2_uniform_TC"] = b2_res["err_test"]
        errors_all["B3_ensemble"] = b3_res["err_test"]
    else:
        print("\n[SKIP] B2/B3: no B1 result.")

    # -- Tables -------------------------------------------------------------
    print("\n" + "=" * 68)
    print("SUMMARY (test set)")
    print("=" * 68)
    df_summary = build_summary_table(errors_all)
    print(df_summary.to_string(index=False))
    df_summary.to_csv(out_dir / "summary_table.csv", index=False)

    scenario_bootstrap_ci(te, errors_all, out_dir,
                          n_boot=cfg.BOOTSTRAP_N, seed=cfg.BOOTSTRAP_SEED,
                          baseline_key="GN_baseline")
    detailed_analysis(te, errors_all, out_dir)

    # -- Plots --------------------------------------------------------------
    print("\n[PLOTS]")
    plot_cdf(errors_all, out_dir / "test_error_cdf.png")
    plot_histogram(errors_all, out_dir / "test_error_histogram.png")
    if l1_res:
        plot_scatter(true_te, l1_res[best_l1]["pred_test"], f"L1_{best_l1}",
                     out_dir / "scatter_L1.png")
    if b3_res:
        plot_scatter(true_te, b3_res["pred_test"], "B3_ensemble",
                     out_dir / "scatter_B3.png")

    # -- JSON summary -------------------------------------------------------
    summary = {
        "data_path": str(data_path),
        "n_train": int(len(tr)),
        "n_val": int(len(va)),
        "n_test": int(len(te)),
        "n_features": int(len(feat_cols)),
        "gn_baseline_mean": float(np.mean(err_gn_te)),
        "gn_baseline_p95": float(np.percentile(err_gn_te, 95)),
    }
    if err_ct_te is not None:
        summary["ctekf_baseline_mean"] = float(np.mean(err_ct_te))
        summary["ctekf_baseline_p95"] = float(np.percentile(err_ct_te, 95))
    if l1_res:
        summary["L1_best"] = best_l1
        summary["L1_mean_test"] = float(np.mean(errors_all[f"L1_{best_l1}"]))
    if b1_res:
        summary["B1_best"] = best_b1
        summary["B1_mean_test"] = float(np.mean(errors_all[f"B1_{best_b1}"]))
    if b2_res:
        summary["B2_uniform_TC_mean_test"] = float(np.mean(errors_all["B2_uniform_TC"]))
        summary["B2_uniform_TC_p95_test"] = float(np.percentile(errors_all["B2_uniform_TC"], 95))
        summary["B2_q_selected"] = float(b2_res["tune"]["q"])
        summary["B2_rmult_selected"] = float(b2_res["tune"]["r_mult"])
    if b3_res:
        summary["B3_best"] = "ensemble"
        summary["B3_mean_test"] = float(np.mean(errors_all["B3_ensemble"]))
        summary["B3_p95_test"] = float(np.percentile(errors_all["B3_ensemble"], 95))
        summary["B3_q_selected"] = float(b3_res["tune"]["q"])
        summary["B3_rmult_selected"] = float(b3_res["tune"]["r_mult"])
        summary["B3_nis_threshold"] = float(cfg.B3_NIS_THRESHOLD)
        summary["B3_sigma_ref_ns"] = float(b3_res["sigma_ref_ns"])
        summary["B3_members"] = list(b3_res["members"])
    summary["bootstrap_replicates"] = int(cfg.BOOTSTRAP_N)
    summary["bootstrap_seed"] = int(cfg.BOOTSTRAP_SEED)
    save_json(out_dir / "final_summary.json", summary)

    print(f"\nOutputs written to: {out_dir}")


if __name__ == "__main__":
    args = parse_args()
    main(args.data, args.out)
