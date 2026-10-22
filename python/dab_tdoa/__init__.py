"""
dab_tdoa: learning-assisted receiver-centric TDOA localization with DAB
signals of opportunity (training and evaluation).

Modules
-------
config    : settings (paths, seeds, model families, EKF grids, bootstrap)
data      : dataset loading, cleaning and the scenario-wise split
features  : leakage-free feature engineering and selection
models    : regressor families, training, prediction, ensembling
gn        : weighted robust Gauss-Newton TDOA solver
ekf       : tightly coupled TDOA CT-EKF (B2, B3)
levels    : L1, B1, B2 and B3
analysis  : summary tables, per-group analysis, bootstrap, plots
utils     : metrics and small helpers
"""
