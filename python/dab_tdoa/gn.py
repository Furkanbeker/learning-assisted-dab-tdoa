"""
Weighted robust Gauss-Newton solver for receiver-centric TDOA, used to
re-solve the position from the B1-corrected TDOAs. REF is the origin.
"""

import numpy as np

from . import config as cfg


def _gn_solve(tx_rel, delta_s, weights=None, x0=None, max_iter=35):
    """Weighted robust Gauss-Newton TDOA localization for one row (REF at the origin)."""
    tx = np.asarray(tx_rel, float).reshape(4, 2)
    d  = np.asarray(delta_s, float).reshape(4)
    w  = np.ones(4) if weights is None else np.clip(
             np.asarray(weights, float), 1e-4, 1e6)
    x  = np.mean(tx, 0) if x0 is None else np.asarray(x0, float)
    ref = np.zeros(2)

    for _ in range(max_iter):
        h = np.zeros(4); H = np.zeros((4, 2))
        for k in range(4):
            sk = tx[k]
            du = np.linalg.norm(x - sk); du = max(du, 1e-9)
            dr = np.linalg.norm(ref - sk)
            h[k]    = (du - dr) / cfg.C_LIGHT
            H[k, 0] = (x[0] - sk[0]) / (cfg.C_LIGHT * du)
            H[k, 1] = (x[1] - sk[1]) / (cfg.C_LIGHT * du)
        r = d - h
        med  = np.median(r)
        mad  = np.median(np.abs(r - med)) + 1e-12
        hk   = max(3.0 * mad, 50e-9)
        hw   = np.minimum(1.0, hk / (np.abs(r) + 1e-12))
        weff = w * hw; sw = np.sqrt(weff)
        Hw = H * sw[:, None]; rw = r * sw
        A = Hw.T @ Hw; b = Hw.T @ rw
        try:
            dx = np.linalg.solve(A, b) if np.linalg.cond(A) < 1e12                  else np.linalg.pinv(Hw) @ rw
        except Exception:
            dx = np.linalg.pinv(Hw) @ rw
        step = np.linalg.norm(dx)
        if step > 500: dx *= 500 / step
        x += dx
        if np.linalg.norm(dx) < 1e-6: break
    return x


def gn_batch(df_part, delta_cols, weight_cols=None):
    """Solve GN for every row of df_part, starting from the original GN estimate."""
    n = len(df_part)
    tx_x = np.column_stack([df_part[f"tx{k}_rel_x"].values for k in range(1, 5)])
    tx_y = np.column_stack([df_part[f"tx{k}_rel_y"].values for k in range(1, 5)])
    deltas = df_part[delta_cols].values.astype(float)
    x0s    = df_part[["gn_est_rel_x","gn_est_rel_y"]].values.astype(float)

    if weight_cols and all(c in df_part.columns for c in weight_cols):
        weights = df_part[weight_cols].values.astype(float)
    else:
        weights = np.ones((n, 4))

    out = np.zeros((n, 2))
    for i in range(n):
        tx_rel = np.column_stack([tx_x[i], tx_y[i]])
        out[i] = _gn_solve(tx_rel, deltas[i], weights[i], x0s[i])
    return out
