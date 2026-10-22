function [overallTable, motionTable] = compute_performance_tables(Tctekf, tableOutDir)
    % COMPUTE_PERFORMANCE_TABLES  GN vs CT-EKF localization error tables.
    %
    % overallTable: mean, median, RMSE, P90/P95/P99 and max error over all rows.
    % motionTable : per-motion-type comparison.
    % Both are printed and saved as CSV in tableOutDir. Standalone use:
    %   T = readtable('results/<run>/dab_soop_tdoa_ctekf.csv');
    %   compute_performance_tables(T, 'results/<run>');
    %
    % Inputs
    %   Tctekf       table with columns gn_pos_err_m, ctekf_pos_err_m and
    %                motion_type
    %   tableOutDir  output folder (default: current folder)

    if nargin < 2 || isempty(tableOutDir)
        tableOutDir = pwd;
    end

    requiredCols = {'gn_pos_err_m', 'ctekf_pos_err_m', 'motion_type'};
    missingCols = setdiff(requiredCols, Tctekf.Properties.VariableNames);

    if ~isempty(missingCols)
        error('Missing required columns in Tctekf: %s', strjoin(missingCols, ', '));
    end

    gnErr    = Tctekf.gn_pos_err_m;
    ctekfErr = Tctekf.ctekf_pos_err_m;

    validMask = isfinite(gnErr) & isfinite(ctekfErr);
    gnErr    = gnErr(validMask);
    ctekfErr = ctekfErr(validMask);

    % ------------------------------------------------
    % Overall GN vs CT-EKF performance
    % ------------------------------------------------

    gnMean    = mean(gnErr);
    gnMedian  = median(gnErr);
    gnRmse    = sqrt(mean(gnErr.^2));
    gnP90     = prctile(gnErr, 90);
    gnP95     = prctile(gnErr, 95);
    gnP99     = prctile(gnErr, 99);
    gnMax     = max(gnErr);

    ekfMean   = mean(ctekfErr);
    ekfMedian = median(ctekfErr);
    ekfRmse   = sqrt(mean(ctekfErr.^2));
    ekfP90    = prctile(ctekfErr, 90);
    ekfP95    = prctile(ctekfErr, 95);
    ekfP99    = prctile(ctekfErr, 99);
    ekfMax    = max(ctekfErr);

    overallTable = table( ...
        ["GN"; "CT-EKF"; "CT-EKF Gain"], ...
        [gnMean; ekfMean; gnMean - ekfMean], ...
        [gnMedian; ekfMedian; gnMedian - ekfMedian], ...
        [gnRmse; ekfRmse; gnRmse - ekfRmse], ...
        [gnP90; ekfP90; gnP90 - ekfP90], ...
        [gnP95; ekfP95; gnP95 - ekfP95], ...
        [gnP99; ekfP99; gnP99 - ekfP99], ...
        [gnMax; ekfMax; gnMax - ekfMax], ...
        'VariableNames', { ...
            'Method', ...
            'Mean_Error_m', ...
            'Median_Error_m', ...
            'RMSE_m', ...
            'P90_m', ...
            'P95_m', ...
            'P99_m', ...
            'Max_Error_m' ...
        } ...
    );

    fprintf('\n');
    fprintf('Overall GN vs CT-EKF Performance\n');
    fprintf('------------------------------------------------------------\n');
    disp(overallTable);

    % ------------------------------------------------
    % Performance per motion type
    % ------------------------------------------------

    motionCol = string(Tctekf.motion_type);
    motionCol = motionCol(validMask);

    % Display order.
    preferredMotionOrder = ["circle"; "line"; "sine"; "sine2"];

    availableMotions = unique(motionCol, 'stable');

    motionOrder = preferredMotionOrder(ismember(preferredMotionOrder, availableMotions));
    extraMotions = setdiff(availableMotions, motionOrder, 'stable');
    motionOrder = [motionOrder; extraMotions];

    numMotions = numel(motionOrder);

    Motion_Type = strings(numMotions, 1);
    N = zeros(numMotions, 1);

    GN_Mean_m = zeros(numMotions, 1);
    CTEKF_Mean_m = zeros(numMotions, 1);
    Gain_m = zeros(numMotions, 1);
    Gain_percent = zeros(numMotions, 1);
    Improved_measurements_percent = zeros(numMotions, 1);
    GN_P95_m = zeros(numMotions, 1);
    CTEKF_P95_m = zeros(numMotions, 1);

    for i = 1:numMotions

        mName = motionOrder(i);
        idx = motionCol == mName;

        g = gnErr(idx);
        e = ctekfErr(idx);

        Motion_Type(i) = mName;
        N(i) = numel(g);

        GN_Mean_m(i) = mean(g);
        CTEKF_Mean_m(i) = mean(e);

        Gain_m(i) = GN_Mean_m(i) - CTEKF_Mean_m(i);
        Gain_percent(i) = 100 * Gain_m(i) / GN_Mean_m(i);

        Improved_measurements_percent(i) = 100 * mean(e < g);

        GN_P95_m(i) = prctile(g, 95);
        CTEKF_P95_m(i) = prctile(e, 95);

    end

    motionTable = table( ...
        Motion_Type, ...
        N, ...
        GN_Mean_m, ...
        CTEKF_Mean_m, ...
        Gain_m, ...
        Gain_percent, ...
        Improved_measurements_percent, ...
        GN_P95_m, ...
        CTEKF_P95_m ...
    );

    fprintf('\n');
    fprintf('GN vs CT-EKF Performance per Motion Type\n');
    fprintf('------------------------------------------------------------\n');
    disp(motionTable);

    % ------------------------------------------------
    % Save tables
    % ------------------------------------------------

    overallFile = fullfile(tableOutDir, 'gn_ctekf_overall.csv');
    motionFile = fullfile(tableOutDir, 'gn_ctekf_by_motion.csv');

    writetable(overallTable, overallFile);
    writetable(motionTable, motionFile);

    fprintf('\n');
    fprintf('Saved final performance tables:\n');
    fprintf('  %s\n', overallFile);
    fprintf('  %s\n', motionFile);

    fprintf('\n');
    fprintf('Short final interpretation:\n');
    fprintf('  Overall CT-EKF mean gain: %.3f m, %.2f %%\n', ...
        gnMean - ekfMean, 100 * (gnMean - ekfMean) / gnMean);

    [bestGain, bestIdx] = max(Gain_percent);
    [worstGain, worstIdx] = min(Gain_percent);

    fprintf('  Best motion type for CT-EKF: %s, gain = %.3f m, %.2f %%\n', ...
        Motion_Type(bestIdx), Gain_m(bestIdx), bestGain);

    fprintf('  Weakest motion type for CT-EKF: %s, gain = %.3f m, %.2f %%\n', ...
        Motion_Type(worstIdx), Gain_m(worstIdx), worstGain);
end
