"""
Tightly coupled TDOA CT-EKF used by B2 and B3.

State x = [px, py, v, psi, omega] (coordinated-turn model). The measurement
vector is the four B1-corrected receiver-centric TDOAs. The per-channel
measurement noise is base_sigma^2 * r_mult * r_scale, with r_scale = 1 for
B2 and the predicted R-scale for B3.
"""

import numpy as np

from . import config as cfg
from .utils import pos_error, val_objective


def _ct_predict(x, dt):
    px, py, v, psi, om = x
    if abs(om) < 1e-7:
        px2 = px + v * dt * np.cos(psi)
        py2 = py + v * dt * np.sin(psi)
    else:
        px2 = px + (v/om)*(np.sin(psi+om*dt) - np.sin(psi))
        py2 = py - (v/om)*(np.cos(psi+om*dt) - np.cos(psi))
    psi2 = np.arctan2(np.sin(psi+om*dt), np.cos(psi+om*dt))
    return np.array([px2, py2, v, psi2, om], float)


def _ct_jacobian(x, dt, eps=1e-5):
    n = len(x)
    F = np.zeros((n, n))
    fx = _ct_predict(x, dt)
    for i in range(n):
        xp = x.copy(); xp[i] += eps
        F[:, i] = (_ct_predict(xp, dt) - fx) / eps
    return F


def _tdoa_hH(state, tx_rel):
    """Receiver-centric TDOA measurement model h(x) and its Jacobian H (REF at the origin)."""
    px, py = state[0], state[1]
    tx = np.asarray(tx_rel, float).reshape(4, 2)
    h = np.zeros(4); H = np.zeros((4, 5))
    for k in range(4):
        sk = tx[k]
        du = max(np.linalg.norm([px-sk[0], py-sk[1]]), 1e-9)
        dr = np.linalg.norm(sk)
        h[k]    = (du - dr) / cfg.C_LIGHT
        H[k, 0] = (px - sk[0]) / (cfg.C_LIGHT * du)
        H[k, 1] = (py - sk[1]) / (cfg.C_LIGHT * du)
    return h, H


def tight_tdoa_ctekf_scenario(df_sc, corr_delta_cols,
                               init_xy, r_scales_ch,
                               base_sigma_s, r_mult, q, dt=1.0):
    """
    Tightly coupled TDOA CT-EKF for one scenario.
    init_xy: (N,2) B1-corrected GN positions (used for initialization)
    r_scales_ch: (N,4) per-channel measurement-noise scale factors
    """
    df_sc = df_sc.sort_values("meas_idx").reset_index(drop=True)
    n   = len(df_sc)
    z   = df_sc[corr_delta_cols].values.astype(float)
    tx_x = np.column_stack([df_sc[f"tx{k}_rel_x"].values for k in range(1, 5)])
    tx_y = np.column_stack([df_sc[f"tx{k}_rel_y"].values for k in range(1, 5)])

    # Initial state from the first two GN positions
    if n >= 2:
        d = init_xy[1] - init_xy[0]
        v0  = float(np.linalg.norm(d))
        ps0 = float(np.arctan2(d[1], d[0])) if v0 > 1e-9 else 0.0
    else:
        v0 = 0.0; ps0 = 0.0
    x = np.array([init_xy[0,0], init_xy[0,1], v0, ps0, 0.0], float)
    P = np.diag([100.**2, 100.**2, 50.**2, np.deg2rad(90.)**2, 0.5**2])
    I = np.eye(5)
    out = np.zeros((n, 2))

    Q_base = q * np.diag([1., 1., 0.5, np.deg2rad(2.), 0.02])**2

    for i in range(n):
        if i > 0:
            F = _ct_jacobian(x, dt)
            x = _ct_predict(x, dt)
            P = F @ P @ F.T + Q_base

        tx_rel = np.column_stack([tx_x[i], tx_y[i]])
        h, H   = _tdoa_hH(x, tx_rel)

        R_diag = (base_sigma_s**2) * r_mult * np.asarray(r_scales_ch[i], float)
        R_diag = np.clip(R_diag, (1e-9)**2, (10e-6)**2)
        R = np.diag(R_diag)

        innov = z[i] - h
        S = H @ P @ H.T + R

        # NIS gating: inflate R for outlying innovations
        try:
            gate = float(innov @ np.linalg.solve(S, innov))
        except Exception:
            gate = 0.0
        if gate > cfg.B3_NIS_THRESHOLD:
            R = R * min(50., gate / cfg.B3_NIS_THRESHOLD)
            S = H @ P @ H.T + R

        K = P @ H.T @ np.linalg.pinv(S)
        x = x + K @ innov
        x[3] = np.arctan2(np.sin(x[3]), np.cos(x[3]))
        x[2] = np.clip(x[2], 0., 150.)
        x[4] = np.clip(x[4], -0.8, 0.8)
        P = (I - K @ H) @ P @ (I - K @ H).T + K @ R @ K.T

        out[i] = x[:2]
    return out


def apply_tight_ekf(df_part, corr_delta_cols, init_xy,
                    r_scales_ch, base_sigma_s, r_mult, q, dt=1.0):
    """Run the tight TDOA CT-EKF on every scenario of df_part."""
    df_part = df_part.copy()
    df_part["_ord"] = np.arange(len(df_part))
    out = np.zeros((len(df_part), 2))

    for sc_id, grp in df_part.groupby("scenario_id"):
        g   = grp.sort_values("meas_idx")
        idx = g["_ord"].values
        out[idx] = tight_tdoa_ctekf_scenario(
            g, corr_delta_cols, init_xy[idx],
            r_scales_ch[idx], base_sigma_s, r_mult, q, dt)
    return out


def tune_ekf(val_df, val_true, val_init, val_r,
             corr_delta_cols, base_sigma_s):
    """Grid search of q and r_mult on the validation set."""
    best = {"score": np.inf, "q": 1.0, "r_mult": 1.0}
    for q in cfg.EKF_Q_GRID:
        for rm in cfg.EKF_RMULT_GRID:
            pred = apply_tight_ekf(val_df, corr_delta_cols, val_init,
                                   val_r, base_sigma_s, rm, q)
            sc = val_objective(pos_error(val_true, pred))
            if sc < best["score"]:
                best = {"score": sc, "q": q, "r_mult": rm}
    print(f"  EKF best: q={best['q']}, r_mult={best['r_mult']}, "
          f"val_obj={best['score']:.4f}")
    return best
