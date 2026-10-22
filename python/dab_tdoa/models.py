"""Regressor families, training, prediction and ensembling."""

import time

import numpy as np
from sklearn.ensemble import ExtraTreesRegressor, HistGradientBoostingRegressor
from sklearn.metrics import mean_absolute_error
from sklearn.multioutput import MultiOutputRegressor

from . import config as cfg


def make_single_model(name: str, random_state: int = cfg.RANDOM_SEED):
    """One regressor family with the fixed hyperparameters of the paper."""
    name = str(name).lower().strip()

    if name == "lgbm":
        try:
            from lightgbm import LGBMRegressor
        except ImportError as exc:
            raise RuntimeError("LightGBM requested but not installed.") from exc
        return MultiOutputRegressor(LGBMRegressor(
            n_estimators=1200, learning_rate=0.030,
            num_leaves=63, subsample=0.85, colsample_bytree=0.85,
            reg_lambda=5.0, reg_alpha=0.05, min_child_samples=15,
            random_state=random_state, n_jobs=-1, verbose=-1,
        ))

    if name == "xgb":
        try:
            from xgboost import XGBRegressor
        except ImportError as exc:
            raise RuntimeError("XGBoost requested but not installed.") from exc
        return MultiOutputRegressor(XGBRegressor(
            n_estimators=1000, max_depth=6, learning_rate=0.030,
            subsample=0.85, colsample_bytree=0.85,
            reg_lambda=5.0, reg_alpha=0.05,
            tree_method="hist", random_state=random_state, n_jobs=-1,
        ))

    if name == "et":
        return ExtraTreesRegressor(
            n_estimators=500, min_samples_leaf=3,
            max_features=0.80, random_state=random_state, n_jobs=-1,
        )

    if name == "hgb":
        return MultiOutputRegressor(HistGradientBoostingRegressor(
            learning_rate=0.04, max_iter=800,
            max_leaf_nodes=48, min_samples_leaf=15,
            l2_regularization=0.02,
            early_stopping=True, validation_fraction=0.10,
            n_iter_no_change=30, random_state=random_state,
        ))

    raise ValueError(f"Unknown model family: {name}")


def make_models() -> dict:
    """All enabled regressor families."""
    requested = []
    if cfg.TRAIN_LGBM:
        requested.append("lgbm")
    if cfg.TRAIN_XGB:
        requested.append("xgb")
    if cfg.TRAIN_ET:
        requested.append("et")
    if cfg.TRAIN_HGB:
        requested.append("hgb")

    models = {}
    for name in requested:
        try:
            models[name] = make_single_model(name, cfg.RANDOM_SEED)
            print(f"  [OK] {name}")
        except (ImportError, RuntimeError) as exc:
            print(f"  [SKIP] {name}: {exc}")

    if not models:
        raise RuntimeError("No model could be created. "
                           "At least scikit-learn (ET/HGB) is required.")
    return models


def _fit_one(name, model, X_tr, y_tr):
    print(f"\n  Training: {name} ...")
    t0 = time.time()
    try:
        model.fit(X_tr, y_tr)
        print(f"  Done: {time.time() - t0:.1f}s")
        return model
    except Exception as e:
        print(f"  [ERROR] {name}: {e}")
        return None


def train_all_models(X_tr, y_tr, scaler_y=None):
    """Train all enabled families; targets are scaled if scaler_y is given."""
    y_fit = y_tr if scaler_y is None else scaler_y.fit_transform(y_tr)
    models = make_models()
    trained = {}
    for name, m in models.items():
        fitted = _fit_one(name, m, X_tr, y_fit)
        if fitted is not None:
            trained[name] = fitted
    return trained


def predict_all(trained, X, scaler_y=None):
    preds = {}
    for name, m in trained.items():
        p = m.predict(X)
        if scaler_y is not None:
            p = scaler_y.inverse_transform(p)
        preds[name] = np.asarray(p, float)
    return preds


def ensemble_weights(preds_val, y_val):
    """Ensemble weights proportional to 1 / validation MAE."""
    scores = {}
    for name, p in preds_val.items():
        mae = float(mean_absolute_error(y_val, p))
        scores[name] = 1.0 / (mae + 1e-12)
    total = sum(scores.values())
    return {n: v / total for n, v in scores.items()}


def make_ensemble(preds, weights):
    return sum(weights[n] * p for n, p in preds.items()
               if n in weights)
