%% ========================================================================
%  generate_dab_tdoa_dataset.m
%
%  Dataset generation for "Learning-Assisted Receiver-Centric TDOA
%  Localization Using DAB Signals of Opportunity".
%
%  Each scenario places four DAB transmitters, a static reference receiver
%  (REF) and a UAV receiver in a 5 km x 5 km field. The UAV follows a
%  circle, line, sine or sine2 trajectory. Per time step: link simulation
%  with a real DAB Mode-I waveform, PRS-based TOA estimation, multi-start
%  weighted GN on UAV-minus-REF TDOAs, and CT-EKF tracking.
%
%  Input : data/dab_iq/basic.cf32 (relative to the repository root)
%  Output: results/dab_soop_tdoa_dataset_<timestamp>/
%% ========================================================================

clear; clc; close all;

%% 0) PATHS

thisDir = fileparts(mfilename('fullpath'));
if isempty(thisDir)
    thisDir = pwd;   % e.g. when the code is run section by section
end
repoRoot = fileparts(thisDir);
addpath(genpath(fullfile(thisDir, 'functions')));

%% 1) USER SETTINGS

% --- DAB waveform -------------------------------------------------------
% DAB Mode-I baseband IQ file (interleaved complex float32, fs = 2.048 MHz).
iqFile = fullfile(repoRoot, 'data', 'dab_iq', 'basic.cf32');
fs = 2.048e6;             % Sampling rate of the IQ file (Hz)
masterDurationSec = 2;    % Length of the waveform segment used (s)

% Carrier frequencies of the four transmitters (Hz), used only for FSPL.
txFreqHz = [195.936e6, 199.360e6, 202.928e6, 206.352e6];

% --- Signal processing --------------------------------------------------
c = 3e8;                  % Propagation speed (m/s)
searchMaxLag = 256;       % Half-width of the PRS TOA search window (samples)

% Observation window length. A Mode-I frame lasts 96 ms, so a 10 ms
% window contains a single PRS.
viewDuration_ms = 10;

% --- Scenarios ------------------------------------------------------------
numScenarios = 10000;     % Number of random scenarios (use e.g. 20 for a quick test)
numMeas = 50;             % UAV measurements (time steps) per scenario
measDt = 1.0;             % Time between measurements (s)

areaMin = 0;              % Square operating field [areaMin, areaMax]^2 (m)
areaMax = 5000;
minRefToTx = 250;         % Minimum REF-to-TX distance (m)

% Per-TX timing offsets (ns), uniform per scenario. They cancel in
% tau_uav - tau_ref but still shift the absolute PRS arrival time.
offsetMinNs = -5000;
offsetMaxNs =  5000;

% Candidate AWGN power levels (normalized units, transmit power = 0 dB).
% One level is drawn per scenario.
noiseCandidates = [1e-14, 5e-14, 1e-13, 5e-13, 1e-12];

% --- Reproducibility ------------------------------------------------------
scenarioSeedBase = 42000; % Scenario i uses seed scenarioSeedBase + i
splitSeed = 2026;         % Seed of the train/val/test split

% --- Execution and outputs ----------------------------------------------
useParallel = true;       % Use a parallel pool if the toolbox is available
maxParallelWorkers = [];  % [] = default pool size
makeFigures = true;       % Save diagnostic figures
outputRoot = fullfile(repoRoot, 'results');

%% 2) LOAD THE DAB IQ WAVEFORM

txIQ_full = load_cf32_iq(iqFile);

fprintf('Loaded IQ file: %s\n', iqFile);
fprintf('Complex samples: %d\n', numel(txIQ_full));
fprintf('Duration: %.3f s\n', numel(txIQ_full)/fs);

% The first masterDurationSec seconds, peak-normalized, are transmitted
% by every TX.
Nmaster = round(masterDurationSec * fs);
assert(numel(txIQ_full) >= Nmaster, 'IQ file shorter than requested master duration.');

masterIQ = double(txIQ_full(1:Nmaster));
masterIQ = masterIQ / max(abs(masterIQ) + eps);

% Identifier of the waveform, stored in every dataset row.
[~, iqName, iqExt] = fileparts(iqFile);
master_waveform_id_val = string([iqName iqExt]);

%% 3) DAB TIMING REFERENCE (NULL SYMBOL AND PRS)

% Locate the Null symbol and the following PRS in the master waveform.
% The PRS useful part is used as the matched-filter template.
dabTimingInfo = extract_dab_timing_reference(masterIQ, fs);
template = dabTimingInfo.prsTemplate;
toaSearchCenterLag = dabTimingInfo.prsStart - 1;

fprintf('DAB timing reference extracted:\n');
fprintf('- Null start sample : %d\n', dabTimingInfo.nullStart);
fprintf('- Null end sample   : %d\n', dabTimingInfo.nullEnd);
fprintf('- PRS start sample  : %d\n', dabTimingInfo.prsStart);
fprintf('- PRS length        : %d samples\n', dabTimingInfo.prsLen);
fprintf('- TOA search center : %d samples\n', toaSearchCenterLag);
fprintf('- Valid PRS centers : %d frames\n', numel(dabTimingInfo.prsSearchCenters));
fprintf('- Null energy ratio : %.4f\n', dabTimingInfo.nullEnergyRatio);

rxKeepLen = round(viewDuration_ms * 1e-3 * fs);
numTx = numel(txFreqHz);

%% 4) PARALLEL POOL (OPTIONAL)

% Each scenario seeds its own RNG, so results do not depend on the pool.
% Without the Parallel Computing Toolbox the parfor loop runs serially.
hasParallelToolbox = ~isempty(ver('parallel')) && ...
    license('test', 'Distrib_Computing_Toolbox');

if useParallel && hasParallelToolbox
    if isempty(gcp('nocreate'))
        if isempty(maxParallelWorkers)
            parpool;
        else
            parpool(maxParallelWorkers);
        end
    end
elseif useParallel
    fprintf('Parallel Computing Toolbox not available: running serially.\n');
end

%% 5) CONFIGURATION STRUCT FOR THE SCENARIO SIMULATION

cfg = struct();
cfg.numTx = numTx;
cfg.numMeas = numMeas;
cfg.numScenarios = numScenarios;
cfg.measDt = measDt;
cfg.areaMin = areaMin;
cfg.areaMax = areaMax;
cfg.minRefToTx = minRefToTx;
cfg.offsetMinNs = offsetMinNs;
cfg.offsetMaxNs = offsetMaxNs;
cfg.noiseCandidates = noiseCandidates;
cfg.scenarioSeedBase = scenarioSeedBase;
cfg.c = c;
cfg.fs = fs;
cfg.txFreqHz = txFreqHz;
cfg.masterIQ = masterIQ;
cfg.rxKeepLen = rxKeepLen;
cfg.template = template;
cfg.dabTimingInfo = dabTimingInfo;
cfg.searchMaxLag = searchMaxLag;
cfg.master_waveform_id_val = master_waveform_id_val;

% Empty row/summary structs that define the output columns.
cfg.rowTemplate = make_empty_dataset_row();
cfg.summaryTemplate = make_empty_summary_row();

%% 6) SIMULATE ALL SCENARIOS

datasetRowsByScenario = cell(numScenarios, 1);
summaryRows(numScenarios,1) = cfg.summaryTemplate;

parfor iscenario = 1:numScenarios
    [rowsThisScenario, summaryThisScenario] = simulate_scenario(iscenario, cfg);
    datasetRowsByScenario{iscenario} = rowsThisScenario;
    summaryRows(iscenario) = summaryThisScenario;
end

%% 7) BUILD TABLES

% datasetBalanced : per-measurement table, all columns (name kept for the
%                   MAT file; no re-balancing is applied).
% scenarioSummary : one row per scenario.
datasetRows = vertcat(datasetRowsByScenario{:});
datasetBalanced = struct2table(datasetRows);
scenarioSummary = struct2table(summaryRows);

%% 8) AI-READY DATASET AND SCENARIO-WISE SPLIT

datasetAI = datasetBalanced(:, get_ai_variable_names());

% 70 / 15 / 15 split at the scenario level.
[trainSc, valSc, testSc, splitLabel] = split_scenarios(datasetAI.scenario_id, splitSeed);
datasetAI.split = splitLabel;

% Learning targets:
%   targetNames     : GN position error (true minus GN estimate, REF frame)
%   tdoaTargetNames : per-channel TDOA error (true minus estimated TDOA, s)
targetNames = {'gn_err_x','gn_err_y'};
tdoaTargetNames = {'delta_err_ch1','delta_err_ch2','delta_err_ch3','delta_err_ch4'};

% Columns that must not be used as model inputs: identifiers, labels,
% ground-truth-based quantities and simulation parameters.
excludedFeatureNames = [ ...
    {'scenario_id','meas_idx', ...
     'motion_type','motion_code', ...
     'geometry_class_est','observation_quality_class', ...
     'uav_rel_x','uav_rel_y', ...
     'gn_err_x','gn_err_y','gn_pos_err_m', ...
     'ctekf_err_x','ctekf_err_y','ctekf_pos_err_m', ...
     'noise_power', ...
     'tx_offset_ch1_ns','tx_offset_ch2_ns','tx_offset_ch3_ns','tx_offset_ch4_ns', ...
     'split'}, ...
    tdoaTargetNames];

% Candidate model inputs: remaining numeric columns.
featureNames = setdiff(datasetAI.Properties.VariableNames, excludedFeatureNames, 'stable');
featureNames = keep_numeric_table_variables(datasetAI, featureNames);

%% 9) SAVE OUTPUTS

timeStamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outputFolder = fullfile(outputRoot, ['dab_soop_tdoa_dataset_' timeStamp]);

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

figFolder = fullfile(outputFolder, 'figures');
if makeFigures && ~exist(figFolder, 'dir')
    mkdir(figFolder);
end

csvBalanced = fullfile(outputFolder, 'dab_soop_tdoa_ctekf.csv');
csvSummary  = fullfile(outputFolder, 'dab_soop_tdoa_summary.csv');
csvAI       = fullfile(outputFolder, 'dab_soop_tdoa_ai_ready_gn_correction.csv');

matBalanced = fullfile(outputFolder, 'dab_soop_tdoa_gn_ctekf.mat');
matAI       = fullfile(outputFolder, 'dab_soop_tdoa_ai_ready_gn_correction.mat');

writetable(datasetBalanced, csvBalanced);
writetable(scenarioSummary, csvSummary);
writetable(datasetAI, csvAI);

save(matBalanced, ...
    'datasetBalanced', 'scenarioSummary', ...
    'txFreqHz', 'noiseCandidates', 'offsetMinNs', 'offsetMaxNs', ...
    'fs', 'masterDurationSec', 'numScenarios', 'numMeas', ...
    '-v7.3');

save(matAI, ...
    'datasetAI', 'featureNames', 'targetNames', 'tdoaTargetNames', ...
    'trainSc', 'valSc', 'testSc', ...
    '-v7.3');

disp(' ');
disp('Saved files:');
disp(['- ' csvBalanced]);
disp(['- ' csvSummary]);
disp(['- ' csvAI]);
disp(['- ' matBalanced]);
disp(['- ' matAI]);

%% 10) FIGURES

if makeFigures
    make_dataset_figures(datasetBalanced, scenarioSummary, figFolder);
    disp(' ');
    disp('Figures saved to:');
    disp(figFolder);
end

%% 11) GN VS CT-EKF PERFORMANCE TABLES

fprintf('\n\n');
fprintf('============================================================\n');
fprintf('FINAL RESULT TABLES: GN vs CT-EKF PERFORMANCE SUMMARY\n');
fprintf('============================================================\n');

[overallTable, motionTable] = ...
    compute_performance_tables(datasetBalanced, outputFolder);

fprintf('============================================================\n\n');

disp(' ');
disp('Dataset generation completed.');
