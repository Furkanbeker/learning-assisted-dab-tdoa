"""
Learning-assisted correction stages.

L1 : position-domain correction. Predicts the GN error (gn_err_x/y) and
     adds it to the GN estimate.
B1 : measurement-domain correction. Predicts the per-link TDOA error
     (delta_err_ch1-4), corrects the TDOAs and re-solves with weighted GN.
B2 : B1 + tightly coupled TDOA CT-EKF with a uniform (validation-tuned) R.
B3 : B1 + tightly coupled TDOA CT-EKF with per-link R-scales predicted by a
     fixed XGB + ET + HGB ensemble trained on out-of-fold B1 residuals.

Model families and EKF parameters are selected on the validation set only.
"""

import numpy as np
from sklearn.model_selection import GroupKFold
from sklearn.preprocessing import RobustScaler

from . import config as cfg
from .ekf import apply_tight_ekf, tune_ekf
from .features import TARGET_B1, TARGET_L1, select_features
from .gn import gn_batch
from .models import (ensemble_weights, make_ensemble, make_single_model,
                     predict_all, train_all_models)
from .utils import compute_metrics, pos_error, print_metrics, val_objective

DELTA_COLS = [f"est_deltaTau_ch{k}" for k in range(1, 5)]
WEIGHT_COLS = [f"tdoa_weight_ch{k}" for k in range(1, 5)]
B3_MEMBERS = ["xgb", "et", "hgb"]


def _header(title):
    print("\n" + "=" * 68)
    print(title)
    print("=" * 68)


# =============================================================================
# L1: direct GN error correction
# =============================================================================

def run_l1(tr, va, te, feat_cols, out_dir):
    _header("L1 - Direct GN Residual Correction")

    X_tr = tr[feat_cols].values.astype(float)
    X_val = va[feat_cols].values.astype(float)
    X_te = te[feat_cols].values.astype(float)

    tgt_cols = [c for c in TARGET_L1 if c in tr.columns]
    if len(tgt_cols) < 2:
        print("  [SKIP] gn_err_x / gn_err_y not found.")
        return None

    y_tr = tr[tgt_cols].values.astype(float)

    sx = RobustScaler()
    X_tr_s = sx.fit_transform(X_tr)
    X_val_s = sx.transform(X_val)
    X_te_s = sx.transform(X_te)

    sy = RobustScaler()
    trained = train_all_models(X_tr_s, y_tr, scaler_y=sy)

    preds_val = predict_all(trained, X_val_s, sy)
    preds_te = predict_all(trained, X_te_s, sy)

    true_val = va[["uav_rel_x", "uav_rel_y"]].values
    true_te = te[["uav_rel_x", "uav_rel_y"]].values
    gn_val = va[["gn_est_rel_x", "gn_est_rel_y"]].values
    gn_te = te[["gn_est_rel_x", "gn_est_rel_y"]].values

    results = {}
    for name in trained:
        corr_val = gn_val + preds_val[name]
        corr_te = gn_te + preds_te[name]
        ev = pos_error(true_val, corr_val)
        et = pos_error(true_te, corr_te)
        results[name] = {
            "val_obj": val_objective(ev),
            "err_val": ev, "err_test": et,
            "pred_val": corr_val, "pred_test": corr_te,
        }
        print_metrics(compute_metrics(f"L1_{name}_val", ev))

    # Inverse-MAE ensemble, weights from the validation targets
    y_val = va[tgt_cols].values.astype(float)
    w = ensemble_weights(preds_val, y_val)
    ens_val = gn_val + make_ensemble(preds_val, w)
    ens_te = gn_te + make_ensemble(preds_te, w)
    ev_ens = pos_error(true_val, ens_val)
    et_ens = pos_error(true_te, ens_te)
    results["ensemble"] = {
        "val_obj": val_objective(ev_ens),
        "err_val": ev_ens, "err_test": et_ens,
        "pred_val": ens_val, "pred_test": ens_te,
    }
    print_metrics(compute_metrics("L1_ensemble_val", ev_ens))

    best = min(results, key=lambda n: results[n]["val_obj"])
    print(f"\n  [L1 SELECTED ON VALIDATION] {best} | "
          f"val_obj={results[best]['val_obj']:.4f}")

    np.save(out_dir / "l1_pred_test.npy", results[best]["pred_test"])
    return results, best


# =============================================================================
# B1: per-link TDOA error correction
# =============================================================================

def b1_oof_predictions(X_tr_raw, y_tr_ns, groups, model_name):
    """Scenario-grouped out-of-fold B1 predictions on the training set.

    Uses the B1 family selected on validation. Scalers are fitted on the
    training part of each fold only.
    """
    model_name = str(model_name).lower().strip()
    if model_name == "ensemble":
        raise ValueError("B1 OOF predictions need a single regressor family.")

    n_splits = min(cfg.B1_OOF_FOLDS, len(np.unique(groups)))
    gkf = GroupKFold(n_splits=n_splits)
    oof = np.zeros_like(y_tr_ns, dtype=float)

    for fold, (ti, vi) in enumerate(gkf.split(X_tr_raw, y_tr_ns, groups), 1):
        print(f"    OOF fold {fold}/{n_splits} | model={model_name} | "
              f"train={len(ti)} val={len(vi)}")

        sx_fold = RobustScaler()
        sy_fold = RobustScaler()
        X_fit = sx_fold.fit_transform(X_tr_raw[ti])
        X_oof = sx_fold.transform(X_tr_raw[vi])
        y_fit = sy_fold.fit_transform(y_tr_ns[ti])

        model = make_single_model(model_name, cfg.RANDOM_SEED)
        model.fit(X_fit, y_fit)
        oof[vi] = sy_fold.inverse_transform(np.asarray(model.predict(X_oof), float))

    mae = float(np.mean(np.abs(oof - y_tr_ns)))
    print(f"  OOF B1 ({model_name}) MAE = {mae:.4f} ns")
    return oof


def _correct_tdoa(df_part, pred_ns):
    """Add the predicted TDOA errors (ns) to the measured TDOAs."""
    out = df_part.copy()
    for k in range(1, 5):
        out[f"est_deltaTau_ch{k}"] = (df_part[f"est_deltaTau_ch{k}"].values
                                      + pred_ns[:, k - 1] * 1e-9)
    return out


def run_b1(tr, va, te, feat_cols, out_dir):
    _header("B1 - Per-Link TDOA Residual Correction")

    tgt_cols = [c for c in TARGET_B1 if c in tr.columns]
    if len(tgt_cols) < 4:
        print("  [SKIP] delta_err_ch1-4 not found.")
        return None

    X_tr = tr[feat_cols].values.astype(float)
    X_val = va[feat_cols].values.astype(float)
    X_te = te[feat_cols].values.astype(float)

    y_tr_ns = tr[tgt_cols].values.astype(float) * 1e9

    sx = RobustScaler()
    X_tr_s = sx.fit_transform(X_tr)
    X_val_s = sx.transform(X_val)
    X_te_s = sx.transform(X_te)

    sy = RobustScaler()
    trained = train_all_models(X_tr_s, y_tr_ns, scaler_y=sy)
    preds_val_ns = predict_all(trained, X_val_s, sy)
    preds_te_ns = predict_all(trained, X_te_s, sy)

    true_val = va[["uav_rel_x", "uav_rel_y"]].values
    true_te = te[["uav_rel_x", "uav_rel_y"]].values

    results = {}
    for name in trained:
        va_corr = _correct_tdoa(va, preds_val_ns[name])
        te_corr = _correct_tdoa(te, preds_te_ns[name])

        gn_val = gn_batch(va_corr, DELTA_COLS, WEIGHT_COLS)
        gn_te = gn_batch(te_corr, DELTA_COLS, WEIGHT_COLS)

        ev = pos_error(true_val, gn_val)
        et = pos_error(true_te, gn_te)

        results[name] = {
            "val_obj": val_objective(ev),
            "err_val": ev, "err_test": et,
            "pred_val": gn_val, "pred_test": gn_te,
            "pred_ns_val": preds_val_ns[name],
            "pred_ns_te": preds_te_ns[name],
            "va_corr": va_corr, "te_corr": te_corr,
        }
        print_metrics(compute_metrics(f"B1_{name}_val", ev))

    # Single families only, so that the selected one can be refitted out-of-fold
    best = min(results, key=lambda n: results[n]["val_obj"])
    print(f"\n  [B1 SELECTED ON VALIDATION] {best} | "
          f"val_obj={results[best]['val_obj']:.4f}")

    print("\n  B1 out-of-fold predictions for the B3 targets ...")
    oof_ns = b1_oof_predictions(X_tr, y_tr_ns, tr["scenario_id"].values, best)

    results[best]["oof_ns"] = oof_ns
    results[best]["tr_corr"] = _correct_tdoa(tr, oof_ns)

    np.save(out_dir / "b1_pred_test.npy", results[best]["pred_test"])
    return results, best


# =============================================================================
# B2 / B3: tightly coupled TDOA CT-EKF
# =============================================================================

def _add_b3_features(df_part, gn_xy, pred_ns):
    """B1-corrected GN position, corrected TDOAs, B1 predictions and innovations."""
    d = df_part.copy()
    d["b1gn_x"] = gn_xy[:, 0]
    d["b1gn_y"] = gn_xy[:, 1]

    for k in range(1, 5):
        d[f"b1_corr_tdoa_ch{k}_ns"] = d[f"est_deltaTau_ch{k}"].values * 1e9
        d[f"b1_pred_ns_ch{k}"] = pred_ns[:, k - 1]

    gx = gn_xy[:, 0]
    gy = gn_xy[:, 1]
    for k in range(1, 5):
        txk_x = d[f"tx{k}_rel_x"].values
        txk_y = d[f"tx{k}_rel_y"].values
        du = np.sqrt((gx - txk_x)**2 + (gy - txk_y)**2)
        dr = np.sqrt(txk_x**2 + txk_y**2)
        inn = (d[f"est_deltaTau_ch{k}"].values * 1e9
               - (du - dr) / cfg.C_LIGHT * 1e9)
        d[f"b3_innov_ch{k}_ns"] = inn
        d[f"b3_abs_innov_ch{k}_ns"] = np.abs(inn)
    return d


B3_EXTRA_FEATURES = (
    ["b1gn_x", "b1gn_y"]
    + [f"b1_corr_tdoa_ch{k}_ns" for k in range(1, 5)]
    + [f"b1_pred_ns_ch{k}" for k in range(1, 5)]
    + [f"b3_innov_ch{k}_ns" for k in range(1, 5)]
    + [f"b3_abs_innov_ch{k}_ns" for k in range(1, 5)]
)


def _to_rscale(log_arr):
    r = np.exp(np.asarray(log_arr, float))
    r[~np.isfinite(r)] = 1.0
    return np.clip(r, cfg.MIN_R_SCALE, cfg.MAX_R_SCALE)


def _run_tight_ekf(name, va_b3, te_b3, init_val, init_te, r_val, r_te,
                   base_sigma_s, true_val, true_te):
    """Tune q and r_mult on validation, then run on validation and test."""
    print(f"\n  [{name}] CT-EKF validation tuning ...")
    tune = tune_ekf(va_b3, true_val, init_val, r_val, DELTA_COLS, base_sigma_s)
    pred_val = apply_tight_ekf(va_b3, DELTA_COLS, init_val, r_val,
                               base_sigma_s, tune["r_mult"], tune["q"])
    pred_te = apply_tight_ekf(te_b3, DELTA_COLS, init_te, r_te,
                              base_sigma_s, tune["r_mult"], tune["q"])
    err_val = pos_error(true_val, pred_val)
    err_te = pos_error(true_te, pred_te)
    print_metrics(compute_metrics(f"{name}_val", err_val))
    print_metrics(compute_metrics(f"{name}_test", err_te))
    return {
        "val_obj": val_objective(err_val),
        "err_val": err_val, "err_test": err_te,
        "pred_val": pred_val, "pred_test": pred_te,
        "tune": tune,
    }


def run_b2_b3(tr, va, te, feat_cols, b1_results, best_b1, out_dir):
    _header("B2 Uniform-R and B3 Learned-R Tight TDOA CT-EKF")

    b1 = b1_results[best_b1]
    tr_corr, va_corr, te_corr = b1["tr_corr"], b1["va_corr"], b1["te_corr"]
    oof_ns, val_ns, te_ns = b1["oof_ns"], b1["pred_ns_val"], b1["pred_ns_te"]

    # B1-corrected GN positions initialize the EKF
    b1_gn_tr = gn_batch(tr_corr, DELTA_COLS, WEIGHT_COLS)
    b1_gn_val = gn_batch(va_corr, DELTA_COLS, WEIGHT_COLS)
    b1_gn_te = gn_batch(te_corr, DELTA_COLS, WEIGHT_COLS)

    true_val = va[["uav_rel_x", "uav_rel_y"]].values
    true_te = te[["uav_rel_x", "uav_rel_y"]].values

    # B3 target: log R-scale from the out-of-fold B1 residuals
    true_err_tr_ns = tr[[f"delta_err_ch{k}" for k in range(1, 5)]].values * 1e9
    resid_tr_ns = true_err_tr_ns - oof_ns

    sigma_ref_ns = max(float(np.median(np.abs(resid_tr_ns))),
                       cfg.B3_RESIDUAL_FLOOR_NS)
    base_sigma_s = sigma_ref_ns * 1e-9
    print(f"  Residual reference scale = {sigma_ref_ns:.4f} ns")

    r_scale_tr = ((np.abs(resid_tr_ns) + cfg.B3_RESIDUAL_FLOOR_NS)
                  / sigma_ref_ns)**2
    r_scale_tr = np.clip(r_scale_tr, cfg.MIN_R_SCALE, cfg.MAX_R_SCALE)
    y_b3_tr = np.log(r_scale_tr)

    tr_b3 = _add_b3_features(tr_corr, b1_gn_tr, oof_ns)
    va_b3 = _add_b3_features(va_corr, b1_gn_val, val_ns)
    te_b3 = _add_b3_features(te_corr, b1_gn_te, te_ns)

    b3_cols = select_features(tr_b3) + [c for c in B3_EXTRA_FEATURES
                                        if c in tr_b3.columns]
    b3_cols = list(dict.fromkeys(b3_cols))

    sx_b3 = RobustScaler()
    X_tr_b3 = sx_b3.fit_transform(tr_b3[b3_cols].values.astype(float))
    X_val_b3 = sx_b3.transform(va_b3[b3_cols].values.astype(float))
    X_te_b3 = sx_b3.transform(te_b3[b3_cols].values.astype(float))

    print("\n  B3 R-scale models ...")
    b3_trained = train_all_models(X_tr_b3, y_b3_tr)

    missing = [m for m in B3_MEMBERS if m not in b3_trained]
    if missing:
        raise RuntimeError("B3 ensemble requires XGB + ExtraTrees + HGB. "
                           "Missing: " + ", ".join(missing))

    b3_preds_val = predict_all(b3_trained, X_val_b3)
    b3_preds_te = predict_all(b3_trained, X_te_b3)

    # B2: uniform R-scale
    b2_result = _run_tight_ekf(
        "B2_uniform_TC", va_b3, te_b3, b1_gn_val, b1_gn_te,
        np.ones((len(va_b3), 4)), np.ones((len(te_b3), 4)),
        base_sigma_s, true_val, true_te)

    # B3: arithmetic mean of the member R-scales
    r_val_ens = np.mean([_to_rscale(b3_preds_val[n]) for n in B3_MEMBERS], axis=0)
    r_te_ens = np.mean([_to_rscale(b3_preds_te[n]) for n in B3_MEMBERS], axis=0)

    b3_result = _run_tight_ekf(
        "B3_ensemble", va_b3, te_b3, b1_gn_val, b1_gn_te,
        r_val_ens, r_te_ens, base_sigma_s, true_val, true_te)
    b3_result.update({
        "name": "ensemble",
        "r_val": r_val_ens, "r_te": r_te_ens,
        "sigma_ref_ns": sigma_ref_ns,
        "members": B3_MEMBERS,
    })

    np.save(out_dir / "b2_uniform_tc_pred_test.npy", b2_result["pred_test"])
    np.save(out_dir / "b3_pred_test.npy", b3_result["pred_test"])
    return b2_result, b3_result
