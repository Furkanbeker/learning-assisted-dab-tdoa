# Dataset

The DAB SoOP TDOA dataset used in the paper, generated with
[`matlab/generate_dab_tdoa_dataset.m`](../matlab/generate_dab_tdoa_dataset.m).

- 10,000 scenarios × 50 measurement epochs = **500,000 rows**
- 4 DAB transmitters, 1 static reference receiver (REF), 1 moving UAV receiver
- 4 motion types (circle, line, sine, sine2), 2,500 scenarios each
- Scenario-disjoint split: 7,000 / 1,500 / 1,500 scenarios
  (350,000 / 75,000 / 75,000 rows) for train / val / test

## Contents

```
dataset_results/
├── dab_soop_tdoa_ctekf/                     Full per-epoch table (149 columns), 10 parts
│   ├── dab_soop_tdoa_ctekf_part01_scenarios_00001-01000.csv.gz
│   ├── ...
│   └── dab_soop_tdoa_ctekf_part10_scenarios_09001-10000.csv.gz
├── dab_soop_tdoa_ai_ready_gn_correction/    AI-ready table (110 columns, incl. `split`), 10 parts
│   ├── dab_soop_tdoa_ai_ready_gn_correction_part01_scenarios_00001-01000.csv.gz
│   ├── ...
│   └── dab_soop_tdoa_ai_ready_gn_correction_part10_scenarios_09001-10000.csv.gz
├── dab_soop_tdoa_summary.csv                One row per scenario (10,000 rows)
├── tables/
│   ├── gn_ctekf_overall.csv                 GN vs LC-CT-EKF error statistics (full dataset)
│   └── gn_ctekf_by_motion.csv               GN vs LC-CT-EKF per motion type (full dataset)
├── figures/
│   ├── png/                                 Selected diagnostic figures (PNG)
│   └── matlab_fig/                          Same figures as editable MATLAB .fig files
└── SHA256SUMS                               Checksums of every file in this folder
```

| Figure | Content |
|---|---|
| `mean_abs_tdoa_error_histogram` | Per-epoch link-averaged absolute TDOA error (Fig. 4 of the paper) |
| `snr_ref_vs_uav_histogram` | Simulation-derived link SNR proxies of REF and UAV (Fig. 5) |
| `peak_ref_vs_uav_histogram` | Normalized PRS correlation peak of REF and UAV |
| `noise_power_vs_gn_error` | GN error vs. AWGN level |
| `uav_positions_colored_by_gn_error` | UAV positions colored by the GN error |
| `scenario_geometry_vs_gn_ctekf_error` | Scenario geometry score vs. GN / LC-CT-EKF error |

`matlab/generate_dab_tdoa_dataset.m` writes these and eight more
diagnostic figures with the same file names.

| Table | Rows | Columns | Uncompressed size | Compressed size |
|---|---|---|---|---|
| `dab_soop_tdoa_ctekf` | 500,000 | 149 | 1.16 GB | 415 MB (10 × ~42 MB) |
| `dab_soop_tdoa_ai_ready_gn_correction` | 500,000 | 110 | 820 MB | 295 MB (10 × ~30 MB) |
| `dab_soop_tdoa_summary.csv` | 10,000 | 38 | 5.4 MB | – |

## Why the large tables are split

GitHub rejects files larger than 100 MB, so the two large tables are
stored as gzip-compressed parts. The split is **lossless**:

- Each part holds 1,000 complete scenarios (50,000 rows); no scenario is
  cut between two parts.
- Each part is a valid, self-contained CSV with the header row, so a single
  part can be opened on its own.
- Concatenating the parts (keeping the header only once) reproduces the
  original MATLAB output **byte for byte**, including its CRLF line endings.

## Loading

**Python (pandas)**, directly from the parts:

```python
import glob
import pandas as pd

files = sorted(glob.glob("dataset_results/dab_soop_tdoa_ai_ready_gn_correction/*.csv.gz"))
df = pd.concat((pd.read_csv(f) for f in files), ignore_index=True)   # 500,000 x 110
```

**MATLAB**, after decompressing the parts with `gunzip`:

```matlab
files = gunzip('dataset_results/dab_soop_tdoa_ctekf/*.csv.gz', tempdir);
parts = cell(numel(files), 1);
for k = 1:numel(files)
    parts{k} = readtable(files{k});
end
T = vertcat(parts{:});
```

## Reassembling the original CSV files

**Linux / macOS / Git Bash**:

```bash
cd dataset_results
zcat dab_soop_tdoa_ctekf/*.csv.gz | awk 'NR==1 || !/^scenario_id,/' > dab_soop_tdoa_ctekf.csv
zcat dab_soop_tdoa_ai_ready_gn_correction/*.csv.gz | awk 'NR==1 || !/^scenario_id,/' > dab_soop_tdoa_ai_ready_gn_correction.csv
```

**Any platform (Python, no extra packages)**:

```python
import glob, gzip, shutil

for name in ["dab_soop_tdoa_ctekf", "dab_soop_tdoa_ai_ready_gn_correction"]:
    parts = sorted(glob.glob(f"dataset_results/{name}/{name}_part*.csv.gz"))
    with open(f"dataset_results/{name}.csv", "wb") as out:
        for i, part in enumerate(parts):
            with gzip.open(part, "rb") as src:
                if i > 0:
                    src.readline()      # skip the repeated header
                shutil.copyfileobj(src, out)
```

The Python pipeline reads the parts directly, so reassembly is not needed
for it:

```bash
cd python
python run_ai_pipeline.py      # default: ../dataset_results/dab_soop_tdoa_ai_ready_gn_correction/
```

## Integrity check

Verify the files in this folder:

```bash
cd dataset_results
sha256sum -c SHA256SUMS
```

SHA-256 of the reassembled files (identical to the original MATLAB output):

| File | SHA-256 |
|---|---|
| `dab_soop_tdoa_ctekf.csv` | `2d59a0c1c82418eb820abdd3f7746e1b37c58ee5c62927df1c11a53e35691542` |
| `dab_soop_tdoa_ai_ready_gn_correction.csv` | `efdc8552eed05e10e936a297bcc6eb6585596b5944c62f65dc3291f6b8133887` |

## Column overview

Each row is one measurement epoch, identified by `scenario_id` (1–10,000)
and `meas_idx` (1–50). Channels `ch1`–`ch4` correspond to the four
transmitters. Positions with `_rel_` are relative coordinates, `_abs_` are
absolute field coordinates (m).

| Group | Columns |
|---|---|
| Identification | `scenario_id`, `meas_idx`, `motion_type`, `motion_code` |
| Transmitter layout | `tx*_rel_x/y`, `tx_centroid_x/y`, `tx_polygon_area`, `tx_equivalent_radius`, `is_ref_inside_tx_polygon`, `ref_to_tx_centroid_dist` |
| Estimated geometry | `gdop_like_est`, `condition_number_est`, `geometry_score_est`, `geometry_class_est`, `is_gn_inside_tx_polygon`, `gn_to_tx_centroid_dist` |
| TDOA | `est_deltaTau_ch*`, `delta_err_ch*`, `tdoa_weight_ch*`, `valid_tdoa_ch*`, `valid_tdoa_count` |
| TOA / correlation quality | `peak_{ref,uav}_ch*`, `toa_conf_{ref,uav}_ch*`, `peak_to_median_*`, `peak_to_second_*`, `snr_{ref,uav}_ch*`, `mean/min_snr_uav`, `mean/min_peak_uav`, `mean/min_toa_conf_uav`, `observation_quality_score/class` |
| Estimates | `gn_est_rel_x/y`, `ctekf_est_rel_x/y`, `ctekf_speed_mps`, `ctekf_heading_rad`, `ctekf_turn_rate_radps` |
| Ground truth and errors | `uav_rel_x/y`, `gn_err_x/y`, `gn_pos_err_m`, `ctekf_err_x/y`, `ctekf_pos_err_m` |
| Simulation parameters | `noise_power`, `tx_offset_ch*_ns` |
| Split (AI-ready only) | `split` ∈ {`train`, `val`, `test`} |

The full table (`dab_soop_tdoa_ctekf`) additionally contains the true
geometry (`*_true`), true TDOAs (`true_deltaTau_ch*`), link distances and
FSPL amplitudes, absolute coordinates, `ctekf_reset_flag`,
`ekf_to_gn_dist_m` and `master_waveform_id`.

Ground truth, errors and simulation parameters are used only as targets or
for evaluation, never as model inputs; the feature construction is in
[`python/dab_tdoa/features.py`](../python/dab_tdoa/features.py).

> Note: `tables/` and the figures are computed by MATLAB over the **full**
> dataset, whereas the results in [`ai_results/`](../ai_results/README.md)
> and in Tables 4–6 of the paper are computed on the **test** split.
