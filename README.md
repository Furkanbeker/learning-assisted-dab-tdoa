# Learning-Assisted Receiver-Centric TDOA Localization Using DAB Signals of Opportunity

Code and data for the paper

> **Learning-Assisted Receiver-Centric TDOA Localization Using DAB Signals of Opportunity**
> &lt;Mustafa Furkan Beker, Abdullah Tan, Khaled Elgammal, Mehmet Kemal Ozdemir&gt;, submitted to *IEEE Access*.

A UAV is localized with time differences of arrival (TDOA) of Digital Audio
Broadcasting (DAB) signals. A static reference receiver (REF) and the UAV
receive the same four DAB transmitters, so the transmitter clock offsets
cancel in the receiver-centric TDOA (UAV minus REF). The repository contains

1. a **MATLAB simulator** that generates the dataset: a real DAB Mode-I
   waveform, PRS-based TOA estimation, a multi-start weighted Gauss-Newton
   (GN) solver and a maneuver-adaptive CT-EKF, and
2. a **Python pipeline** that trains the learning-assisted corrections
   (L1, B1, B3) and produces the result tables and figures, and
3. the **DAB generation tools** (GUI + ODR scripts) used to create the DAB
   waveform and to transmit it with an ADALM-PLUTO for an over-the-air test,
   and
4. the **dataset** used in the paper (10,000 scenarios, 500,000 epochs) in
   [`dataset_results/`](dataset_results/README.md).

```
 DAB IQ waveform ─► link simulation ─► PRS TOA ─► TDOA ─► GN ─► CT-EKF ─► dataset (CSV)
   (data/)          (FSPL + AWGN +      (matched                              │
                     TX timing offset)   filter)                               ▼
                                                     Python: L1 / B1 / B3 training, evaluation, figures
```

## Repository structure

```
.
├── matlab/
│   ├── generate_dab_tdoa_dataset.m   Main script (all settings at the top)
│   └── functions/
│       ├── signal/        IQ loading, DAB Null/PRS detection, channel, TOA estimation
│       ├── geometry/      Random TX/REF layout, GDOP, geometry score
│       ├── trajectory/    UAV paths (circle, line, sine, sine2)
│       ├── localization/  TDOA weights, multi-start weighted GN, reliability check
│       ├── tracking/      Maneuver-adaptive CT-EKF
│       ├── simulation/    One scenario / one time step of the simulation
│       ├── dataset/       Output columns, observation quality, train/val/test split
│       ├── evaluation/    GN vs CT-EKF tables (Tables 2 and 3), diagnostic figures
│       └── utils/
├── python/
│   ├── run_ai_pipeline.py            Trains and evaluates L1 / B1 / B3
│   ├── make_paper_figures.py         GN vs EKF vs proposed-method figures
│   ├── requirements.txt
│   └── dab_tdoa/                     Package (config, features, models, GN, EKF, ...)
├── dab_generation/                   DAB waveform generation and TX GUI (see its README)
├── data/dab_iq/
│   ├── basic.cf32                    DAB Mode-I baseband IQ waveform
│   └── basic.json                    Metadata of the waveform
├── dataset_results/                  Dataset of the paper (see its README)
│   ├── dab_soop_tdoa_ctekf/          Full per-epoch table, 10 gzip parts
│   ├── dab_soop_tdoa_ai_ready_gn_correction/   AI-ready table, 10 gzip parts
│   ├── dab_soop_tdoa_summary.csv     One row per scenario
│   ├── tables/                       GN vs CT-EKF tables (Tables 2 and 3)
│   └── figures/                      Diagnostic figures (PNG + MATLAB .fig)
├── media/                            Photos and video of the over-the-air test
└── results/                          Created by the code (not tracked by git)
```

## Requirements

**MATLAB** (tested with &lt;MATLAB release&gt;)
- Base MATLAB. Parallel Computing Toolbox is optional: without it the
  scenario loop runs serially and gives identical results.

**Python** 3.9 or newer
```bash
cd python
pip install -r requirements.txt
```
The paper results were obtained with &lt;numpy / pandas / scikit-learn /
xgboost versions&gt;.

## Data

`data/dab_iq/basic.cf32` is a standard-compliant DAB Mode-I baseband
waveform: interleaved complex float32 samples (I, Q, I, Q, ...) at
2.048 MS/s, 5.96 s long. It was generated from an ETI stream carrying one
120 kbps audio service ("MediComm-DAB"); see `basic.json`. It was produced
with the tools in [`dab_generation/`](dab_generation/README.md) from
`dab_generation/audio/basic.wav`. The simulator
uses the first 2 s of the file as the transmitted waveform of all four
transmitters.

The file is about 98 MB and is stored with Git LFS (see `.gitattributes`).
Install Git LFS before cloning:

```bash
git lfs install
git clone <repository URL>
```

If the file is only a small text pointer, run `git lfs pull`.

## Dataset

The dataset used in the paper is included in
[`dataset_results/`](dataset_results/README.md), so it can be used without
running the simulator: the full table (149 columns), the AI-ready table
with the train/val/test `split` (110 columns), the per-scenario summary,
Tables 2 and 3, and the diagnostic figures.

GitHub does not accept files larger than 100 MB, so the two large tables
(1.16 GB and 820 MB as CSV) are stored as ten gzip-compressed parts each.
Every part contains 1,000 complete scenarios and its own header row, and
the parts reassemble byte for byte into the original CSV files (SHA-256
checksums are provided). To load the AI-ready table directly:

```python
import glob
import pandas as pd

files = sorted(glob.glob("dataset_results/dab_soop_tdoa_ai_ready_gn_correction/*.csv.gz"))
df = pd.concat((pd.read_csv(f) for f in files), ignore_index=True)
```

To reassemble the original CSV files (e.g. for `--data`):

```bash
cd dataset_results
zcat dab_soop_tdoa_ai_ready_gn_correction/*.csv.gz | awk 'NR==1 || !/^scenario_id,/' > dab_soop_tdoa_ai_ready_gn_correction.csv
zcat dab_soop_tdoa_ctekf/*.csv.gz | awk 'NR==1 || !/^scenario_id,/' > dab_soop_tdoa_ctekf.csv
```

A platform-independent Python version and the integrity check are given
in [`dataset_results/README.md`](dataset_results/README.md).

## Quick start

**1. Generate the dataset (MATLAB)**

Open `matlab/generate_dab_tdoa_dataset.m` and run it. For a quick test,
set `numScenarios = 20` in the USER SETTINGS section first. The full
dataset (10,000 scenarios x 50 measurements = 500,000 rows) takes much
longer; a parallel pool is used automatically if available.

Outputs in `results/dab_soop_tdoa_dataset_<timestamp>/`:

| File | Content |
|---|---|
| `dab_soop_tdoa_ctekf.csv` | Full per-measurement table (all columns) |
| `dab_soop_tdoa_summary.csv` | One row per scenario |
| `dab_soop_tdoa_ai_ready_gn_correction.csv` | AI-ready table with the `split` column (input of the Python pipeline) |
| `dab_soop_tdoa_gn_ctekf.mat` | Full and summary tables, simulation settings |
| `dab_soop_tdoa_ai_ready_gn_correction.mat` | AI-ready table, feature/target names, split scenario IDs |
| `table2_overall_gn_ctekf.csv` | GN vs CT-EKF error statistics (Table 2) |
| `table3_motion_gn_ctekf.csv` | GN vs CT-EKF per motion type (Table 3) |
| `figures/` | Diagnostic figures |

**2. Train and evaluate (Python)**

```bash
cd python
python run_ai_pipeline.py          # uses the newest dataset in ../results
python make_paper_figures.py
```

To use the included dataset instead of generating a new one, reassemble the
AI-ready CSV (see [Dataset](#dataset)) and run

```bash
python run_ai_pipeline.py    --data ../dataset_results/dab_soop_tdoa_ai_ready_gn_correction.csv
python make_paper_figures.py --data ../dataset_results/dab_soop_tdoa_ai_ready_gn_correction.csv
```

Use `--data <csv>` to select a specific dataset and `--out <folder>` to
change the output folder (default `results/ai_results/`). Outputs:
`summary_table.csv`, `detailed_analysis.csv`, `final_summary.json`, the
test predictions `l1/b1/b3_pred_test.npy`, plots, and the paper figures in
`paper_figures_gn_ekf_proposed/`.

## Method overview

| Method | Description |
|---|---|
| GN | Multi-start weighted robust Gauss-Newton on the receiver-centric TDOAs |
| CT-EKF | Maneuver-adaptive constant-turn EKF on the GN fixes |
| L1 | Regression of the GN position error, added to the GN estimate |
| B1 | Regression of the per-channel TDOA error; corrected TDOAs are re-solved with weighted GN |
| B3 | B1 + regression of a per-channel measurement-noise scale, used by a tightly coupled TDOA CT-EKF |

Each level trains XGBoost, ExtraTrees and HistGradientBoosting models and
an inverse-MAE ensemble. The best model of each level, and the final
"proposed method" in the figures, are selected with a validation
objective (mean + weighted P90/P95/P99 error). The test set is used only
for reporting.

Leakage protection: the split is done per scenario, so a trajectory never
appears in two subsets. True positions, true TDOAs and errors are used
only as targets, and simulation parameters (noise power, TX timing
offsets) are never used as features (`python/dab_tdoa/features.py`).

## Reference results

Scenario-disjoint test set (1,500 scenarios, 75,000 measurements), as
reported in Table 5 of the paper:

| Method | Mean (m) | Median (m) | RMSE (m) | P95 (m) |
|---|---|---|---|---|
| GN (temporally seeded) | 16.39 | 14.95 | 19.04 | 32.93 |
| LC-CT-EKF | 15.59 | 14.18 | 18.15 | 31.55 |
| L1 (HistGradientBoosting) | 14.93 | 13.37 | 17.60 | 31.04 |
| B1 (XGBoost) | 4.91 | 3.42 | 6.91 | 14.22 |
| B2 (uniform covariance) | 4.78 | 3.41 | 6.55 | 13.56 |
| B3 (ensemble) | 3.95 | 2.65 | 5.68 | 11.83 |

## Simulation model and notes

- Modeled: FSPL at each carrier frequency, AWGN, and a per-transmitter
  timing offset (uniform in ±5 µs). Not modeled: shadowing, multipath,
  NLOS bias, Doppler, CFO/SRO, receiver clock errors and fading.
- All four transmitters reuse the same baseband waveform; the carrier
  frequency enters only through FSPL. Each TX-RX link is simulated
  independently.
- The received observation window is 10 ms. A DAB Mode-I frame lasts
  96 ms, so the TOA estimator uses one PRS per link.
- Reproducibility: scenario *i* uses the seed `42000 + i` and the split
  uses the seed `2026`, so the dataset does not depend on the parallel
  execution order. Python uses `RANDOM_SEED = 42`.
- LightGBM is optional and disabled by default (`dab_tdoa/config.py`).
  The paper results were obtained without it; enabling it changes the
  ensembles and the B1 out-of-fold model.
- The MATLAB tables (Tables 2 and 3) are computed over the full dataset,
  whereas the Python results are computed on the test split.

## Over-the-air test

As a sanity check, the waveform was transmitted with an ADALM-PLUTO SDR on
DAB channel 8A (195.936 MHz) using the tools in
[`dab_generation/`](dab_generation/README.md), and the "MediComm-DAB"
service was decoded by a commercial DAB radio and a car head unit
(`media/`):

| | |
|---|---|
| ![SDR transmitter](media/sdr_transmitter_setup.jpeg) | ![Car head unit](media/car_head_unit_reception.jpeg) |

`media/dab_radio_reception.jpeg` and `media/over_the_air_test_car.mov` show
the reception on a DAB radio and a short recording of the test.

## Citation

```bibtex
@article{<key>,
  title   = {Learning-Assisted Receiver-Centric TDOA Localization Using DAB Signals of Opportunity},
  author  = {<authors>},
  journal = {IEEE Access},
  year    = {<year>},
  note    = {submitted}
}
```

## Contact

&lt;Mustafa Furkan Beker, mustafafurkanbeker@gmail.com&gt;
