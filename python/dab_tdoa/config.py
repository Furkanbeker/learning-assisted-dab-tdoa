"""
Settings of the AI pipeline.

run_ai_pipeline.py and make_paper_figures.py set DATA_PATH and OUT_DIR
from their command-line arguments; all other values are changed here.
"""

from pathlib import Path

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parents[2]

# AI-ready table: a CSV file or a folder of *.csv.gz parts.
# None = the dataset included in dataset_results/.
DATA_PATH = None
DEFAULT_DATA_PATH = (REPO_ROOT / "dataset_results"
                     / "dab_soop_tdoa_ai_ready_gn_correction")

OUT_DIR = REPO_ROOT / "results" / "ai_results"

# -----------------------------------------------------------------------------
# Physics and reproducibility
# -----------------------------------------------------------------------------
C_LIGHT = 3e8          # m/s
RANDOM_SEED = 42

# -----------------------------------------------------------------------------
# Split and features
# -----------------------------------------------------------------------------
# Use the scenario-wise 'split' column written by MATLAB.
USE_EXISTING_SPLIT = True

# Normalized measurement index as a feature.
USE_MEAS_IDX = True

# -----------------------------------------------------------------------------
# Regressor families
# -----------------------------------------------------------------------------
# Paper results: XGBoost, ExtraTrees and HistGradientBoosting.
TRAIN_LGBM = False
TRAIN_XGB = True
TRAIN_ET = True
TRAIN_HGB = True

# Scenario-grouped folds of the B1 out-of-fold predictions (B3 targets).
B1_OOF_FOLDS = 5

# -----------------------------------------------------------------------------
# B2 / B3 tight TDOA CT-EKF
# -----------------------------------------------------------------------------
B3_RESIDUAL_FLOOR_NS = 5.0
MIN_R_SCALE = 0.05
MAX_R_SCALE = 200.0

# Process-noise and R-multiplier grids, searched on the validation set.
EKF_Q_GRID = [0.01, 0.1, 1.0, 3.0, 10.0, 30.0, 100.0, 300.0, 1000.0]
EKF_RMULT_GRID = [0.10, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0]

# NIS gate, chi2(4 dof, 0.99).
B3_NIS_THRESHOLD = 13.2767

# -----------------------------------------------------------------------------
# Scenario-level paired bootstrap (test set, reporting only)
# -----------------------------------------------------------------------------
BOOTSTRAP_N = 5000
BOOTSTRAP_SEED = 2026
