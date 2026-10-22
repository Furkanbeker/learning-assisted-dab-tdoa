"""
Leakage-free feature engineering and feature selection.

Only quantities that are observable in a real system are used as model
inputs. Ground-truth positions and errors, true TDOAs and simulation
parameters (noise power, TX offsets) are excluded.
"""

import numpy as np
import pandas as pd

from . import config as cfg


def build_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Engineered features that are observable in a real system.

    NOT used (leakage):
        uav_rel_x/y, gn_err_x/y, ctekf_err, true_deltaTau,
        delta_err, geometry_score_true, gdop_true,
        noise_power (simulation parameter)

    Used:
        TX positions relative to REF, GN estimate, TDOA measurements,
        PRS peak/confidence/quality, SNR, geometry proxies at the GN
        position, GN innovations (measured minus predicted TDOA), meas_idx
    """
    df = df.copy()
    eps = 1e-12

    # -- TDOA in ns and in meters --------------------------------
    for k in range(1, 5):
        col = f"est_deltaTau_ch{k}"
        df[f"tdoa_ch{k}_ns"] = df[col] * 1e9
        df[f"tdoa_ch{k}_m"]  = df[col] * cfg.C_LIGHT

    tdoa_ns_cols = [f"tdoa_ch{k}_ns" for k in range(1, 5)]
    df["tdoa_mean_ns"]   = df[tdoa_ns_cols].mean(axis=1)
    df["tdoa_std_ns"]    = df[tdoa_ns_cols].std(axis=1).fillna(0)
    df["tdoa_range_ns"]  = df[tdoa_ns_cols].max(axis=1) - df[tdoa_ns_cols].min(axis=1)
    df["tdoa_abs_mean_ns"] = df[tdoa_ns_cols].abs().mean(axis=1)

    # -- SNR -----------------------------------------------------
    snr_uav = [f"snr_uav_ch{k}" for k in range(1, 5)]
    snr_ref = [f"snr_ref_ch{k}" for k in range(1, 5)]
    if all(c in df.columns for c in snr_uav):
        df["snr_uav_mean"] = df[snr_uav].mean(axis=1)
        df["snr_uav_min"]  = df[snr_uav].min(axis=1)
        df["snr_uav_std"]  = df[snr_uav].std(axis=1).fillna(0)
    if all(c in df.columns for c in snr_ref):
        df["snr_ref_mean"] = df[snr_ref].mean(axis=1)
        df["snr_ref_min"]  = df[snr_ref].min(axis=1)

    # -- Correlation peak ----------------------------------------
    pk_uav = [f"peak_uav_ch{k}" for k in range(1, 5)]
    pk_ref = [f"peak_ref_ch{k}" for k in range(1, 5)]
    df["peak_uav_mean"] = df[pk_uav].mean(axis=1)
    df["peak_uav_min"]  = df[pk_uav].min(axis=1)
    df["peak_uav_max"]  = df[pk_uav].max(axis=1)
    df["peak_uav_std"]  = df[pk_uav].std(axis=1).fillna(0)
    df["peak_ref_mean"] = df[pk_ref].mean(axis=1)
    df["peak_ref_min"]  = df[pk_ref].min(axis=1)

    for k in range(1, 5):
        r = df[f"peak_ref_ch{k}"].values
        u = df[f"peak_uav_ch{k}"].values
        df[f"peak_ratio_ch{k}"]     = u / (r + eps)
        df[f"log_peak_ratio_ch{k}"] = np.log(np.clip(u / (r + eps), eps, None))

    # -- TOA confidence ------------------------------------------
    conf_uav = [f"toa_conf_uav_ch{k}" for k in range(1, 5)]
    conf_ref = [f"toa_conf_ref_ch{k}" for k in range(1, 5)]
    if all(c in df.columns for c in conf_uav):
        df["conf_uav_mean"] = df[conf_uav].mean(axis=1)
        df["conf_uav_min"]  = df[conf_uav].min(axis=1)
        df["conf_uav_std"]  = df[conf_uav].std(axis=1).fillna(0)
    if all(c in df.columns for c in conf_ref):
        df["conf_ref_mean"] = df[conf_ref].mean(axis=1)
        df["conf_ref_min"]  = df[conf_ref].min(axis=1)

    # -- Peak-to-median / peak-to-second (log scale) -------------
    for k in range(1, 5):
        for side in ("ref", "uav"):
            col = f"peak_to_median_{side}_ch{k}"
            if col in df.columns:
                df[f"log_ptm_{side}_ch{k}"] = np.log10(
                    np.clip(df[col].values, eps, None)
                )
            col2 = f"peak_to_second_{side}_ch{k}"
            if col2 in df.columns:
                df[f"log_pts_{side}_ch{k}"] = np.log10(
                    np.clip(df[col2].values, eps, None)
                )

    # -- TX geometry (REF is the origin) -------------------------
    tx_x = np.column_stack([df[f"tx{k}_rel_x"].values for k in range(1, 5)])
    tx_y = np.column_stack([df[f"tx{k}_rel_y"].values for k in range(1, 5)])

    df["tx_centroid_x"] = tx_x.mean(axis=1)
    df["tx_centroid_y"] = tx_y.mean(axis=1)

    # Pairwise TX distances
    pair_id = 0
    pair_dists = []
    for i in range(4):
        for j in range(i + 1, 4):
            pair_id += 1
            d = np.sqrt((tx_x[:, i] - tx_x[:, j])**2 +
                        (tx_y[:, i] - tx_y[:, j])**2)
            df[f"tx_pair_{pair_id}_m"] = d
            pair_dists.append(d)
    pair_dists = np.column_stack(pair_dists)
    df["tx_pair_mean_m"] = pair_dists.mean(axis=1)
    df["tx_pair_min_m"]  = pair_dists.min(axis=1)
    df["tx_pair_std_m"]  = pair_dists.std(axis=1)

    # REF-to-TX distances (REF = [0, 0])
    ref_to_tx = []
    for k in range(1, 5):
        d = np.sqrt(df[f"tx{k}_rel_x"].values**2 +
                    df[f"tx{k}_rel_y"].values**2)
        df[f"ref_to_tx{k}_m"] = d
        ref_to_tx.append(d)
    ref_to_tx = np.column_stack(ref_to_tx)
    df["ref_to_tx_mean_m"] = ref_to_tx.mean(axis=1)
    df["ref_to_tx_min_m"]  = ref_to_tx.min(axis=1)
    df["ref_to_tx_max_m"]  = ref_to_tx.max(axis=1)
    df["ref_to_tx_std_m"]  = ref_to_tx.std(axis=1)

    # -- Quantities derived from the GN estimate -----------------
    gx = df["gn_est_rel_x"].values
    gy = df["gn_est_rel_y"].values

    df["gn_radius_m"]   = np.sqrt(gx**2 + gy**2)
    df["gn_bearing_rad"] = np.arctan2(gy, gx)
    df["gn_to_centroid_m"] = np.sqrt(
        (gx - df["tx_centroid_x"].values)**2 +
        (gy - df["tx_centroid_y"].values)**2
    )

    innov_list = []
    abs_innov_list = []
    for k in range(1, 5):
        txk_x = df[f"tx{k}_rel_x"].values
        txk_y = df[f"tx{k}_rel_y"].values

        d_uav = np.sqrt((gx - txk_x)**2 + (gy - txk_y)**2)
        d_ref = np.sqrt(txk_x**2 + txk_y**2)

        df[f"gn_to_tx{k}_m"] = d_uav

        # TDOA predicted from the GN position (ns)
        pred_ns = (d_uav - d_ref) / cfg.C_LIGHT * 1e9
        df[f"gn_pred_tdoa_ch{k}_ns"] = pred_ns

        # Innovation = measured - predicted TDOA
        innov = df[f"tdoa_ch{k}_ns"].values - pred_ns
        df[f"innovation_ch{k}_ns"]     = innov
        df[f"abs_innovation_ch{k}_ns"] = np.abs(innov)
        innov_list.append(innov)
        abs_innov_list.append(np.abs(innov))

    innov_arr     = np.column_stack(innov_list)
    abs_innov_arr = np.column_stack(abs_innov_list)
    df["innov_mean_ns"]     = innov_arr.mean(axis=1)
    df["innov_std_ns"]      = innov_arr.std(axis=1)
    df["abs_innov_mean_ns"] = abs_innov_arr.mean(axis=1)
    df["abs_innov_max_ns"]  = abs_innov_arr.max(axis=1)
    df["abs_innov_min_ns"]  = abs_innov_arr.min(axis=1)

    # Geometry proxy computed at the GN position (no leakage)
    gdop_proxy, cond_proxy = _geometry_proxy(df, gx, gy)
    df["gn_gdop_proxy"]       = gdop_proxy
    df["gn_cond_proxy"]       = cond_proxy
    df["log10_gn_gdop_proxy"] = np.log10(np.clip(gdop_proxy, eps, None))
    df["log10_gn_cond_proxy"] = np.log10(np.clip(cond_proxy, eps, None))

    # -- Measurement index ---------------------------------------
    if cfg.USE_MEAS_IDX and "meas_idx" in df.columns:
        df["meas_idx_norm"] = df["meas_idx"].astype(float) /                               max(float(df["meas_idx"].max()), 1.0)

    return df


def _geometry_proxy(df: pd.DataFrame,
                    bx: np.ndarray,
                    by: np.ndarray):
    """GDOP and condition-number proxies at the GN position."""
    n = len(df)
    gdop = np.zeros(n)
    cond = np.zeros(n)
    tx_x = np.column_stack([df[f"tx{k}_rel_x"].values for k in range(1, 5)])
    tx_y = np.column_stack([df[f"tx{k}_rel_y"].values for k in range(1, 5)])

    for i in range(n):
        H = np.zeros((4, 2))
        for k in range(4):
            vx = bx[i] - tx_x[i, k]
            vy = by[i] - tx_y[i, k]
            r  = np.sqrt(vx**2 + vy**2)
            if r > 1e-9:
                H[k] = [vx / r, vy / r]
        F = H.T @ H
        try:
            Finv = np.linalg.pinv(F)
            gdop[i] = float(np.sqrt(np.trace(Finv)))
            cond[i] = float(np.linalg.cond(F))
        except Exception:
            gdop[i] = 1e6
            cond[i] = 1e12

    return np.clip(gdop, 0, 1e6), np.clip(cond, 0, 1e12)


# =============================================================================
# Feature and target definitions
# =============================================================================

# Raw columns of the AI-ready CSV that do not leak ground truth
_RAW_SAFE = [
    # TX coordinates (relative to REF)
    "tx1_rel_x","tx1_rel_y","tx2_rel_x","tx2_rel_y",
    "tx3_rel_x","tx3_rel_y","tx4_rel_x","tx4_rel_y",
    # GN estimate (solver output, not the true position)
    "gn_est_rel_x","gn_est_rel_y",
    # Raw TDOA values
    "est_deltaTau_ch1","est_deltaTau_ch2",
    "est_deltaTau_ch3","est_deltaTau_ch4",
    # TDOA quality metrics
    "tdoa_weight_ch1","tdoa_weight_ch2","tdoa_weight_ch3","tdoa_weight_ch4",
    "valid_tdoa_ch1","valid_tdoa_ch2","valid_tdoa_ch3","valid_tdoa_ch4",
    "valid_tdoa_count",
    # Peak
    "peak_ref_ch1","peak_ref_ch2","peak_ref_ch3","peak_ref_ch4",
    "peak_uav_ch1","peak_uav_ch2","peak_uav_ch3","peak_uav_ch4",
    # Conf
    "toa_conf_ref_ch1","toa_conf_ref_ch2","toa_conf_ref_ch3","toa_conf_ref_ch4",
    "toa_conf_uav_ch1","toa_conf_uav_ch2","toa_conf_uav_ch3","toa_conf_uav_ch4",
    # Peak-to-median / second
    "peak_to_median_ref_ch1","peak_to_median_ref_ch2",
    "peak_to_median_ref_ch3","peak_to_median_ref_ch4",
    "peak_to_median_uav_ch1","peak_to_median_uav_ch2",
    "peak_to_median_uav_ch3","peak_to_median_uav_ch4",
    "peak_to_second_ref_ch1","peak_to_second_ref_ch2",
    "peak_to_second_ref_ch3","peak_to_second_ref_ch4",
    "peak_to_second_uav_ch1","peak_to_second_uav_ch2",
    "peak_to_second_uav_ch3","peak_to_second_uav_ch4",
    # SNR proxies (simulation-derived, see the paper)
    "snr_ref_ch1","snr_ref_ch2","snr_ref_ch3","snr_ref_ch4",
    "snr_uav_ch1","snr_uav_ch2","snr_uav_ch3","snr_uav_ch4",
    "mean_snr_uav","min_snr_uav",
    "mean_peak_uav","min_peak_uav",
    "mean_toa_conf_uav","min_toa_conf_uav",
    # Observation quality score (partly simulation-derived)
    "observation_quality_score",
    # Geometry at the GN estimate (no leakage)
    "gdop_like_est","condition_number_est","geometry_score_est",
    "is_ref_inside_tx_polygon","ref_to_tx_centroid_dist",
    "is_gn_inside_tx_polygon","gn_to_tx_centroid_dist",
    # REF-to-TX distances (known in a real system)
    "distance_ref_ch1_m","distance_ref_ch2_m",
    "distance_ref_ch3_m","distance_ref_ch4_m",
]

# Engineered features (created by build_features)
_ENGINEERED = [
    "tdoa_ch1_ns","tdoa_ch2_ns","tdoa_ch3_ns","tdoa_ch4_ns",
    "tdoa_ch1_m","tdoa_ch2_m","tdoa_ch3_m","tdoa_ch4_m",
    "tdoa_mean_ns","tdoa_std_ns","tdoa_range_ns","tdoa_abs_mean_ns",
    "snr_uav_mean","snr_uav_min","snr_uav_std",
    "snr_ref_mean","snr_ref_min",
    "peak_uav_mean","peak_uav_min","peak_uav_max","peak_uav_std",
    "peak_ref_mean","peak_ref_min",
    "peak_ratio_ch1","peak_ratio_ch2","peak_ratio_ch3","peak_ratio_ch4",
    "log_peak_ratio_ch1","log_peak_ratio_ch2",
    "log_peak_ratio_ch3","log_peak_ratio_ch4",
    "conf_uav_mean","conf_uav_min","conf_uav_std",
    "conf_ref_mean","conf_ref_min",
    "log_ptm_uav_ch1","log_ptm_uav_ch2","log_ptm_uav_ch3","log_ptm_uav_ch4",
    "log_pts_uav_ch1","log_pts_uav_ch2","log_pts_uav_ch3","log_pts_uav_ch4",
    "tx_centroid_x","tx_centroid_y",
    "tx_pair_1_m","tx_pair_2_m","tx_pair_3_m",
    "tx_pair_4_m","tx_pair_5_m","tx_pair_6_m",
    "tx_pair_mean_m","tx_pair_min_m","tx_pair_std_m",
    "ref_to_tx1_m","ref_to_tx2_m","ref_to_tx3_m","ref_to_tx4_m",
    "ref_to_tx_mean_m","ref_to_tx_min_m","ref_to_tx_max_m","ref_to_tx_std_m",
    "gn_radius_m","gn_bearing_rad","gn_to_centroid_m",
    "gn_to_tx1_m","gn_to_tx2_m","gn_to_tx3_m","gn_to_tx4_m",
    "gn_pred_tdoa_ch1_ns","gn_pred_tdoa_ch2_ns",
    "gn_pred_tdoa_ch3_ns","gn_pred_tdoa_ch4_ns",
    "innovation_ch1_ns","innovation_ch2_ns",
    "innovation_ch3_ns","innovation_ch4_ns",
    "abs_innovation_ch1_ns","abs_innovation_ch2_ns",
    "abs_innovation_ch3_ns","abs_innovation_ch4_ns",
    "innov_mean_ns","innov_std_ns",
    "abs_innov_mean_ns","abs_innov_max_ns","abs_innov_min_ns",
    "gn_gdop_proxy","gn_cond_proxy",
    "log10_gn_gdop_proxy","log10_gn_cond_proxy",
    "meas_idx_norm",
]

# Columns that must never be used as features (ground truth, labels,
# simulation parameters). Any column whose name contains one of these
# patterns is dropped.
_LEAKAGE_PATTERNS = [
    "uav_rel","uav_abs","gn_err","ctekf_err",
    "pos_err","true_deltaTau","delta_err",
    "geometry_score_true","gdop_like_true","condition_number_true",
    "is_uav_inside_tx_polygon_true","uav_to_tx_centroid_dist_true",
    "noise_power","tx_offset_ch",
    "nlos_bias","shadowing","rician","rmsdelay",
    "master_waveform","split","motion_type","motion_code",
]


def select_features(df: pd.DataFrame) -> list:
    """Return the available, leakage-free feature columns of df."""
    candidates = list(dict.fromkeys(_RAW_SAFE + _ENGINEERED))
    available  = [c for c in candidates if c in df.columns]
    safe       = [c for c in available
                  if not any(p in c.lower() for p in _LEAKAGE_PATTERNS)]
    return safe


# L1 target: GN position error (x, y)
TARGET_L1 = ["gn_err_x", "gn_err_y"]

# B1 target: per-link TDOA error (s)
TARGET_B1 = ["delta_err_ch1", "delta_err_ch2",
             "delta_err_ch3", "delta_err_ch4"]
