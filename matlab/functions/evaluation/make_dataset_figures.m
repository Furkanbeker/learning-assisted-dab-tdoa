function make_dataset_figures(datasetBalanced, scenarioSummary, figFolder)
    % Save diagnostic figures (.png and .fig) of the generated dataset.

    fig = figure('Name','UAV Relative Positions Colored by GN Error','Visible','off');
    scatter(datasetBalanced.uav_rel_x, datasetBalanced.uav_rel_y, 18, datasetBalanced.gn_pos_err_m, 'filled');
    axis equal; grid on; colorbar;
    xlabel('UAV Relative X (m)'); ylabel('UAV Relative Y (m)');
    title('UAV Relative Positions Colored by GN Position Error');
    saveas(fig, fullfile(figFolder, 'uav_positions_colored_by_gn_error.png'));
    savefig(fig, fullfile(figFolder, 'uav_positions_colored_by_gn_error.fig'));
    close(fig);

    fig = figure('Name','Estimated Geometry Score Histogram','Visible','off');
    histogram(datasetBalanced.geometry_score_est, 30); grid on;
    xlabel('Estimated Geometry Score'); ylabel('Count');
    title('Distribution of Estimated Geometry Score');
    saveas(fig, fullfile(figFolder, 'geometry_score_est_histogram.png'));
    savefig(fig, fullfile(figFolder, 'geometry_score_est_histogram.fig'));
    close(fig);

    fig = figure('Name','GN Error Histogram by Estimated Geometry Class','Visible','off');
    hold on; grid on;
    cls = string(datasetBalanced.geometry_class_est);
    histogram(datasetBalanced.gn_pos_err_m(cls=="good"), 30, 'Normalization','probability');
    histogram(datasetBalanced.gn_pos_err_m(cls=="medium"), 30, 'Normalization','probability');
    histogram(datasetBalanced.gn_pos_err_m(cls=="bad"), 30, 'Normalization','probability');
    xlabel('GN Position Error (m)'); ylabel('Probability');
    title('GN Position Error Histogram: Estimated Geometry Classes');
    legend({'Good','Medium','Bad'}, 'Location','best');
    saveas(fig, fullfile(figFolder, 'gn_error_by_geometry_class_est.png'));
    savefig(fig, fullfile(figFolder, 'gn_error_by_geometry_class_est.fig'));
    close(fig);

    meanAbsDeltaErr_ns = mean(abs([ ...
        datasetBalanced.delta_err_ch1, datasetBalanced.delta_err_ch2, ...
        datasetBalanced.delta_err_ch3, datasetBalanced.delta_err_ch4]), 2) * 1e9;

    fig = figure('Name','Mean Absolute TDOA Error Histogram','Visible','off');
    histogram(meanAbsDeltaErr_ns, 35); grid on;
    xlabel('Mean Absolute TDOA Error (ns)'); ylabel('Count');
    title('PRS-Based TDOA Error Distribution');
    saveas(fig, fullfile(figFolder, 'mean_abs_tdoa_error_histogram.png'));
    savefig(fig, fullfile(figFolder, 'mean_abs_tdoa_error_histogram.fig'));
    close(fig);

    fig = figure('Name','Estimated Geometry Score vs GN Error','Visible','off');
    scatter(datasetBalanced.geometry_score_est, datasetBalanced.gn_pos_err_m, 15, 'filled');
    grid on; xlabel('Estimated Geometry Score'); ylabel('GN Position Error (m)');
    title('Estimated Geometry Score vs GN Position Error');
    saveas(fig, fullfile(figFolder, 'geometry_score_est_vs_gn_error.png'));
    savefig(fig, fullfile(figFolder, 'geometry_score_est_vs_gn_error.fig'));
    close(fig);

    fig = figure('Name','Estimated GDOP-like vs GN Error','Visible','off');
    scatter(datasetBalanced.gdop_like_est, datasetBalanced.gn_pos_err_m, 15, 'filled');
    grid on; xlabel('Estimated GDOP-like'); ylabel('GN Position Error (m)');
    title('Estimated GDOP-like Score vs GN Position Error');
    saveas(fig, fullfile(figFolder, 'gdop_est_vs_gn_error.png'));
    savefig(fig, fullfile(figFolder, 'gdop_est_vs_gn_error.fig'));
    close(fig);

    fig = figure('Name','Estimated Geometry Class Counts','Visible','off');
    classNames = ["good","medium","bad"];
    counts = zeros(size(classNames));
    for i = 1:numel(classNames)
        counts(i) = sum(string(datasetBalanced.geometry_class_est) == classNames(i));
    end
    bar(categorical(classNames), counts); grid on;
    xlabel('Estimated Geometry Class'); ylabel('Number of Samples');
    title('Sample Distribution by Estimated Geometry Class');
    saveas(fig, fullfile(figFolder, 'geometry_class_est_counts.png'));
    savefig(fig, fullfile(figFolder, 'geometry_class_est_counts.fig'));
    close(fig);

    fig = figure('Name','Scenario Mean Error vs True Geometry Score','Visible','off');
    hold on; grid on;
    scatter(scenarioSummary.mean_geometry_score_true, scenarioSummary.mean_gn_pos_err_m, 35, 'filled');
    scatter(scenarioSummary.mean_geometry_score_true, scenarioSummary.mean_ctekf_pos_err_m, 35, 'filled');
    xlabel('Scenario Mean True Geometry Score'); ylabel('Scenario Mean Position Error (m)');
    title('Scenario-Level Geometry Quality vs GN / CT-EKF Error');
    legend({'GN','CT-EKF'}, 'Location','best');
    saveas(fig, fullfile(figFolder, 'scenario_geometry_vs_gn_ctekf_error.png'));
    savefig(fig, fullfile(figFolder, 'scenario_geometry_vs_gn_ctekf_error.fig'));
    close(fig);

    peakRef = mean([datasetBalanced.peak_ref_ch1, datasetBalanced.peak_ref_ch2, datasetBalanced.peak_ref_ch3, datasetBalanced.peak_ref_ch4], 2);
    peakUav = mean([datasetBalanced.peak_uav_ch1, datasetBalanced.peak_uav_ch2, datasetBalanced.peak_uav_ch3, datasetBalanced.peak_uav_ch4], 2);

    fig = figure('Name','Correlation Peak Ref vs UAV Histogram','Visible','off');
    hold on; grid on;
    histogram(peakRef, 30, 'Normalization','probability');
    histogram(peakUav, 30, 'Normalization','probability');
    xlabel('Mean Correlation Peak'); ylabel('Probability');
    title('PRS Correlation Peak Histogram: Reference RX vs UAV RX');
    legend({'Reference RX','UAV RX'}, 'Location','best');
    saveas(fig, fullfile(figFolder, 'peak_ref_vs_uav_histogram.png'));
    savefig(fig, fullfile(figFolder, 'peak_ref_vs_uav_histogram.fig'));
    close(fig);

    fig = figure('Name','Noise Power vs GN Error','Visible','off');
    scatter(datasetBalanced.noise_power, datasetBalanced.gn_pos_err_m, 15, 'filled');
    set(gca, 'XScale', 'log'); grid on;
    xlabel('Noise Power'); ylabel('GN Position Error (m)');
    title('AWGN Noise Power vs GN Position Error');
    saveas(fig, fullfile(figFolder, 'noise_power_vs_gn_error.png'));
    savefig(fig, fullfile(figFolder, 'noise_power_vs_gn_error.fig'));
    close(fig);

    snrRef = mean([datasetBalanced.snr_ref_ch1, datasetBalanced.snr_ref_ch2, datasetBalanced.snr_ref_ch3, datasetBalanced.snr_ref_ch4], 2);
    snrUav = mean([datasetBalanced.snr_uav_ch1, datasetBalanced.snr_uav_ch2, datasetBalanced.snr_uav_ch3, datasetBalanced.snr_uav_ch4], 2);

    fig = figure('Name','SNR Ref vs UAV Histogram','Visible','off');
    hold on; grid on;
    histogram(snrRef, 30, 'Normalization','probability');
    histogram(snrUav, 30, 'Normalization','probability');
    xlabel('Mean Link SNR (dB)'); ylabel('Probability');
    title('FSPL + AWGN SNR Distribution: Reference RX vs UAV RX');
    legend({'Reference RX','UAV RX'}, 'Location','best');
    saveas(fig, fullfile(figFolder, 'snr_ref_vs_uav_histogram.png'));
    savefig(fig, fullfile(figFolder, 'snr_ref_vs_uav_histogram.fig'));
    close(fig);

    fig = figure('Name','SNR vs GN Error','Visible','off');
    scatter(snrUav, datasetBalanced.gn_pos_err_m, 15, 'filled');
    grid on; xlabel('Mean UAV Link SNR (dB)'); ylabel('GN Position Error (m)');
    title('SNR vs GN Position Error');
    saveas(fig, fullfile(figFolder, 'snr_vs_gn_error.png'));
    savefig(fig, fullfile(figFolder, 'snr_vs_gn_error.fig'));
    close(fig);

    fig = figure('Name','GN vs CT-EKF Position Error Histogram','Visible','off');
    hold on; grid on;
    histogram(datasetBalanced.gn_pos_err_m, 40);
    histogram(datasetBalanced.ctekf_pos_err_m, 40);
    xlabel('Position Error (m)'); ylabel('Count');
    title('GN vs CT-EKF Position Error Distribution');
    legend({'GN','CT-EKF'}, 'Location','best');
    saveas(fig, fullfile(figFolder, 'gn_vs_ctekf_position_error_histogram.png'));
    savefig(fig, fullfile(figFolder, 'gn_vs_ctekf_position_error_histogram.fig'));
    close(fig);

    fig = figure('Name','Observation Quality Score vs GN / CT-EKF Error','Visible','off');
    hold on; grid on;
    scatter(datasetBalanced.observation_quality_score, datasetBalanced.gn_pos_err_m, 15, 'filled');
    scatter(datasetBalanced.observation_quality_score, datasetBalanced.ctekf_pos_err_m, 15, 'filled');
    xlabel('Observation Quality Score'); ylabel('Position Error (m)');
    title('Observation Quality vs Localization Error');
    legend({'GN','CT-EKF'}, 'Location','best');
    saveas(fig, fullfile(figFolder, 'observation_quality_score_vs_error.png'));
    savefig(fig, fullfile(figFolder, 'observation_quality_score_vs_error.fig'));
    close(fig);
end
