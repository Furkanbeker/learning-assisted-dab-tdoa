# AI results

Test-set results of the learning-assisted localization pipeline
([`python/run_ai_pipeline.py`](../python/run_ai_pipeline.py)) on the dataset
in [`dataset_results/`](../dataset_results/README.md). These are the values
reported in Tables 5 and 6 of the paper.

- Scenario-disjoint split: 7,000 / 1,500 / 1,500 scenarios
  (350,000 / 75,000 / 75,000 epochs) for train / val / test
- Regressor families, ensemble members and EKF covariance scales are
  selected on the validation set; the test set is used only for reporting.

| File | Content |
|---|---|
| [`summary_table.csv`](summary_table.csv) | Mean, median, RMSE, P75, P90, P95, P99 and max error of every method (Table 5) |
| [`detailed_analysis.csv`](detailed_analysis.csv) | Mean and P95 error per motion type (Table 6), estimated geometry class and observation-quality class |
| [`scenario_bootstrap_ci.csv`](scenario_bootstrap_ci.csv) | 95% confidence intervals of the mean error and of the gain vs. GN (paired bootstrap over the 1,500 test scenarios, 5,000 replicates, seed 2026) |

Method names in the files:

| File name | Paper name | Description |
|---|---|---|
| `GN_baseline` | GN (temporally seeded) | Multi-start weighted robust Gauss-Newton |
| `CT-EKF_baseline` | LC-CT-EKF | Loosely coupled adaptive CT-EKF on the GN fixes |
| `L1_hgb` | L1-HGB | GN position-error correction (HistGradientBoosting) |
| `B1_xgb` | B1-XGB | Per-link TDOA-error correction + weighted GN (XGBoost) |
| `B2_uniform_TC` | B2-Uniform | B1 + tightly coupled TDOA CT-EKF, uniform R |
| `B3_ensemble` | B3-Ensemble | B1 + tightly coupled TDOA CT-EKF, R-scales from the XGB/ET/HGB ensemble |

## Overall test results

| Method | Mean (m) | Median (m) | RMSE (m) | P90 (m) | P95 (m) | P99 (m) | Max (m) | Gain vs. GN (%) |
|---|---|---|---|---|---|---|---|---|
| GN | 16.39 | 14.95 | 19.04 | 28.22 | 32.93 | 47.54 | 190.39 | – |
| LC-CT-EKF | 15.59 | 14.18 | 18.15 | 26.94 | 31.55 | 45.79 | 188.96 | 4.85 |
| L1-HGB | 14.93 | 13.37 | 17.60 | 26.14 | 31.04 | 46.11 | 187.10 | 8.86 |
| B1-XGB | 4.91 | 3.42 | 6.91 | 10.75 | 14.22 | 22.45 | 147.80 | 70.02 |
| B2-Uniform | 4.78 | 3.41 | 6.55 | 10.35 | 13.56 | 21.17 | 81.47 | 70.83 |
| B3-Ensemble | **3.95** | **2.65** | **5.68** | **8.66** | **11.83** | **19.89** | **80.32** | **75.88** |

B3-Ensemble mean error, 95% CI: 3.82–4.09 m; gain vs. GN, 95% CI: 75.10–76.65%.

## Test results per motion type

| Motion | Epochs | GN mean (m) | LC-CT-EKF mean (m) | B1 mean (m) | B3 mean (m) | GN P95 (m) | B3 P95 (m) |
|---|---|---|---|---|---|---|---|
| Circle | 18,500 | 16.31 | 15.44 | 5.00 | 3.91 | 33.12 | 11.70 |
| Line | 19,150 | 16.31 | 15.55 | 4.66 | 3.61 | 32.20 | 10.69 |
| Sine | 17,800 | 16.33 | 15.52 | 4.85 | 3.75 | 32.36 | 11.27 |
| Double-sine (`sine2`) | 19,550 | 16.59 | 15.84 | 5.13 | 4.52 | 33.96 | 13.30 |

## Selected configuration

| Item | Value |
|---|---|
| L1 regressor (validation) | HistGradientBoosting |
| B1 regressor (validation) | XGBoost |
| B3 OOF targets | 5-fold scenario-grouped B1-XGB, fold-local scaling |
| B3 reference scale σ_ref | 5.9464 ns |
| B2 covariance scales (α_Q, α_R) | 10, 0.5 |
| B3 covariance scales (α_Q, α_R) | 100, 5 |
| Innovation (NIS) threshold | 13.28 (χ², 4 dof, 99%) |

The corresponding figures are in [`figures/`](../figures/) (Figs. 6 and 7).

## Reproducing

```bash
cd python
pip install -r requirements.txt
python run_ai_pipeline.py
python make_paper_figures.py
```

Outputs are written to `results/ai_results/`. Besides the three tables above,
a run also writes `feature_list.csv`, `final_summary.json`, the test-set
position estimates (`l1/b1/b2_uniform_tc/b3_pred_test.npy`), diagnostic plots
and `paper_figures/`.
