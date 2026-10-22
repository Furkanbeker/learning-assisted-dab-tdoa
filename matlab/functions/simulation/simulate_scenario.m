function [scenarioRows, summary] = simulate_scenario(iscenario, cfg)
    % SIMULATE_SCENARIO  Simulate one random scenario and build its dataset rows.
    %
    % Inputs
    %   iscenario  scenario index (also used to seed the random generator)
    %   cfg        configuration struct built in generate_dab_tdoa_dataset.m
    %
    % Outputs
    %   scenarioRows  cfg.numMeas x 1 struct array (one dataset row each)
    %   summary       1 x 1 struct with the scenario-level summary

    % Unpack the configuration.
    numTx                  = cfg.numTx;
    numMeas                = cfg.numMeas;
    numScenarios           = cfg.numScenarios;
    areaMin                = cfg.areaMin;
    areaMax                = cfg.areaMax;
    minRefToTx             = cfg.minRefToTx;
    offsetMinNs            = cfg.offsetMinNs;
    offsetMaxNs            = cfg.offsetMaxNs;
    noiseCandidates        = cfg.noiseCandidates;
    measDt                 = cfg.measDt;
    c                      = cfg.c;
    scenarioSeedBase       = cfg.scenarioSeedBase;
    rowTemplate            = cfg.rowTemplate;
    summaryTemplate        = cfg.summaryTemplate;
    master_waveform_id_val = cfg.master_waveform_id_val;

    % Per-scenario seed: results do not depend on parfor execution order.
    rng(scenarioSeedBase + iscenario, 'twister');
    localRowCells = cell(numMeas, 1);

    fprintf('Scenario %d / %d\n', iscenario, numScenarios);

    %% Geometry and UAV motion
    % txRel: TX positions relative to REF (frame of the AI features).

    [txPos, refPos, uavPath, uavCenter, uavScale, startDeg, clockwise, motionType] = ...
        generate_random_geometry_and_uav_motion(numTx, areaMin, areaMax, minRefToTx, numMeas, iscenario);

    txRel = txPos - refPos;

    txGeomInfo = compute_tx_polygon_info(txPos);
    refGeomInfo = compute_point_geometry_info(refPos, txPos);

    %% TX timing offsets and AWGN level

    txTimingOffset_ns = offsetMinNs + (offsetMaxNs - offsetMinNs) * rand(1, numTx);
    txTimingOffset_s  = txTimingOffset_ns * 1e-9;

    noisePower = noiseCandidates(randi(numel(noiseCandidates)));

    fprintf('Scenario %d | txTimingOffset_ns = [%.2f %.2f %.2f %.2f]\n', ...
        iscenario, txTimingOffset_ns(1), txTimingOffset_ns(2), ...
        txTimingOffset_ns(3), txTimingOffset_ns(4));

    %% Scenario-level result arrays

    % results columns:
    %   1 meas index | 2-3 true UAV x,y | 4-5 GN x,y | 6 GN error (m)
    %   7 mean |TDOA error| (ns) | 8 mean PRS peak
    %   9 UAV inside TX hull (true) | 10 REF inside TX hull
    %   11 geometry score (true) | 12 GDOP-like (true)
    %   13 condition number (true) | 14 TX hull area
    %   15 UAV-to-TX-centroid distance (true) | 16 REF-to-TX-centroid distance
    results = zeros(numMeas, 16);

    % ekfResults columns:
    %   1 meas index | 2-3 CT-EKF x,y | 4 CT-EKF error (m)
    %   5 speed (m/s) | 6 heading (rad) | 7 turn rate (rad/s)
    ekfResults = zeros(numMeas, 7);

    % CT-EKF tracker state (initialized at the first measurement).
    tracker = struct('state', [], 'P', [], 'prevGnPos', [], ...
        'prevPrevGnPos', [], 'resetCount', 0);

    scenarioMeanSnr = zeros(numMeas,1);
    scenarioValidCount = zeros(numMeas,1);
    scenarioObsQuality = zeros(numMeas,1);

    %% Measurement loop

    for imeas = 1:numMeas

        truePos = uavPath(imeas,:);
        rxPosAll = [refPos; truePos];

        % Simulate every TX-RX link and estimate its PRS-based TOA.
        links = simulate_link_measurements( ...
            txPos, rxPosAll, txTimingOffset_s, noisePower, cfg);

        tauTrue          = links.tauTrue;
        tauHat           = links.tauHat;
        peakVals         = links.peakVals;
        toaConfVals      = links.toaConfVals;
        peakToMedianVals = links.peakToMedianVals;
        peakToSecondVals = links.peakToSecondVals;
        snrVals          = links.snrVals;
        distanceVals     = links.distanceVals;
        ampVals          = links.ampVals;

        % Receiver-centric TDOA per TX: tau_uav - tau_ref.
        trueDelta = (tauTrue(:,2) - tauTrue(:,1)).';
        estDelta  = (tauHat(:,2)  - tauHat(:,1)).';
        deltaErrForMetrics = estDelta - trueDelta;
        deltaErrForTarget = trueDelta - estDelta;

        % TDOA weights (from TOA confidences) and validity flags.
        maxExpectedDelta_s = sqrt(2) * (areaMax - areaMin) / c + 1.5e-6;
        [tdoaWeights, validTdoa] = compute_tdoa_weights( ...
            toaConfVals, estDelta, maxExpectedDelta_s);

        meanDeltaErr_ns = mean(abs(deltaErrForMetrics)) * 1e9;
        maxDeltaErr_ns = max(abs(deltaErrForMetrics)) * 1e9;
        meanPeak = mean(peakVals(:));

        % GN initial point: TX centroid at the first step, otherwise the
        % current CT-EKF position.
        if imeas == 1 || isempty(tracker.state)
            x0 = mean(txPos,1);
        else
            x0 = tracker.state(1:2).';
        end

        [xHat, gnInfo] = localize_receiver_centric_weighted_gn_multistart( ...
            txPos, refPos, estDelta(:), c, x0, tdoaWeights, validTdoa, areaMin, areaMax);

        posErr_m = norm(xHat - truePos);

        % Geometry at the true position (evaluation only) and at the GN
        % estimate (AI features).
        [uavGeomTrueInfo, gdopTrueInfo, geometry_score_true, geometry_class_true] = ...
            evaluate_point_geometry(truePos, txPos, refPos, refGeomInfo, txGeomInfo);

        [uavGeomEstInfo, gdopEstInfo, geometry_score_est, geometry_class_est] = ...
            evaluate_point_geometry(xHat, txPos, refPos, refGeomInfo, txGeomInfo);

        %% Adaptive CT-EKF filtering of the GN estimate
        % Uses observable quantities only.
        [tracker, ekfPos, ekfToGnDist, ekfWasReset] = update_adaptive_ctekf( ...
            tracker, imeas, xHat, gnInfo, validTdoa, tdoaWeights, toaConfVals, ...
            geometry_score_est, gdopEstInfo, txGeomInfo, refPos, ...
            areaMin, areaMax, measDt);

        ekfState = tracker.state;   % [px; py; v; psi; omega]
        ekfErr_m = norm(ekfPos - truePos);

        ekfResults(imeas,:) = [ ...
            imeas, ekfPos(1), ekfPos(2), ekfErr_m, ...
            ekfState(3), ekfState(4), ekfState(5)];

        results(imeas,:) = [ ...
            imeas, truePos(1), truePos(2), xHat(1), xHat(2), ...
            posErr_m, meanDeltaErr_ns, meanPeak, ...
            double(uavGeomTrueInfo.isInsideTxPolygon), ...
            double(refGeomInfo.isInsideTxPolygon), ...
            geometry_score_true, ...
            gdopTrueInfo.gdop_like, ...
            gdopTrueInfo.condition_number, ...
            txGeomInfo.area, ...
            uavGeomTrueInfo.pointToCentroidDist, ...
            refGeomInfo.pointToCentroidDist];

        %% Dataset row
        % _rel: relative to REF, _abs: field frame. Errors are true minus estimate.

        row = rowTemplate;

        uavAbs = truePos;
        uavRel = uavAbs - refPos;
        gnEstAbs = xHat;
        gnEstRel = gnEstAbs - refPos;
        gnErr = uavRel - gnEstRel;
        ekfEstAbs = ekfPos;
        ekfEstRel = ekfEstAbs - refPos;
        ekfErr = uavRel - ekfEstRel;

        peak_ref = peakVals(:,1).';
        peak_uav = peakVals(:,2).';
        conf_ref = toaConfVals(:,1).';
        conf_uav = toaConfVals(:,2).';
        ptm_ref = peakToMedianVals(:,1).';
        ptm_uav = peakToMedianVals(:,2).';
        pts_ref = peakToSecondVals(:,1).';
        pts_uav = peakToSecondVals(:,2).';
        snr_ref = snrVals(:,1).';
        snr_uav = snrVals(:,2).';
        dist_ref = distanceVals(:,1).';
        dist_uav = distanceVals(:,2).';
        amp_ref = ampVals(:,1).';
        amp_uav = ampVals(:,2).';

        mean_snr_uav = mean(snr_uav);
        min_snr_uav = min(snr_uav);
        mean_peak_uav = mean(peak_uav);
        min_peak_uav = min(peak_uav);
        mean_conf_uav = mean(conf_uav);
        min_conf_uav = min(conf_uav);
        valid_tdoa_count = sum(validTdoa);

        [observation_quality_score, observation_quality_class] = classify_observation_quality( ...
            mean_snr_uav, mean_peak_uav, mean_conf_uav, valid_tdoa_count, numTx);

        combined_tdoa_geometry_metric_est = maxDeltaErr_ns * gdopEstInfo.condition_number;

        row.scenario_id = iscenario;
        row.meas_idx = imeas;
        row.motion_type = string(motionType);
        row.motion_code = motion_type_to_code(motionType);

        row.tx1_rel_x = txRel(1,1); row.tx1_rel_y = txRel(1,2);
        row.tx2_rel_x = txRel(2,1); row.tx2_rel_y = txRel(2,2);
        row.tx3_rel_x = txRel(3,1); row.tx3_rel_y = txRel(3,2);
        row.tx4_rel_x = txRel(4,1); row.tx4_rel_y = txRel(4,2);

        row.tx_centroid_x = txGeomInfo.centroid(1);
        row.tx_centroid_y = txGeomInfo.centroid(2);
        row.tx_polygon_area = txGeomInfo.area;
        row.tx_equivalent_radius = txGeomInfo.equivalentRadius;

        row.is_ref_inside_tx_polygon = double(refGeomInfo.isInsideTxPolygon);
        row.ref_to_tx_centroid_dist = refGeomInfo.pointToCentroidDist;

        row.is_gn_inside_tx_polygon = double(uavGeomEstInfo.isInsideTxPolygon);
        row.gn_to_tx_centroid_dist = uavGeomEstInfo.pointToCentroidDist;
        row.gdop_like_est = gdopEstInfo.gdop_like;
        row.condition_number_est = gdopEstInfo.condition_number;
        row.geometry_score_est = geometry_score_est;
        row.geometry_class_est = string(geometry_class_est);

        row.is_uav_inside_tx_polygon_true = double(uavGeomTrueInfo.isInsideTxPolygon);
        row.uav_to_tx_centroid_dist_true = uavGeomTrueInfo.pointToCentroidDist;
        row.gdop_like_true = gdopTrueInfo.gdop_like;
        row.condition_number_true = gdopTrueInfo.condition_number;
        row.geometry_score_true = geometry_score_true;
        row.geometry_class_true = string(geometry_class_true);

        row.mean_abs_delta_err_ns = meanDeltaErr_ns;
        row.max_abs_delta_err_ns = maxDeltaErr_ns;
        row.combined_tdoa_geometry_metric_est = combined_tdoa_geometry_metric_est;

        for kk = 1:numTx
            row.(sprintf('est_deltaTau_ch%d',kk)) = estDelta(kk);
            row.(sprintf('true_deltaTau_ch%d',kk)) = trueDelta(kk);
            row.(sprintf('delta_err_ch%d',kk)) = deltaErrForTarget(kk);
            row.(sprintf('tdoa_weight_ch%d',kk)) = tdoaWeights(kk);
            row.(sprintf('valid_tdoa_ch%d',kk)) = double(validTdoa(kk));
            row.(sprintf('peak_ref_ch%d',kk)) = peak_ref(kk);
            row.(sprintf('peak_uav_ch%d',kk)) = peak_uav(kk);
            row.(sprintf('toa_conf_ref_ch%d',kk)) = conf_ref(kk);
            row.(sprintf('toa_conf_uav_ch%d',kk)) = conf_uav(kk);
            row.(sprintf('peak_to_median_ref_ch%d',kk)) = ptm_ref(kk);
            row.(sprintf('peak_to_median_uav_ch%d',kk)) = ptm_uav(kk);
            row.(sprintf('peak_to_second_ref_ch%d',kk)) = pts_ref(kk);
            row.(sprintf('peak_to_second_uav_ch%d',kk)) = pts_uav(kk);
            row.(sprintf('snr_ref_ch%d',kk)) = snr_ref(kk);
            row.(sprintf('snr_uav_ch%d',kk)) = snr_uav(kk);
            row.(sprintf('distance_ref_ch%d_m',kk)) = dist_ref(kk);
            row.(sprintf('distance_uav_ch%d_m',kk)) = dist_uav(kk);
            row.(sprintf('fspl_amp_ref_ch%d',kk)) = amp_ref(kk);
            row.(sprintf('fspl_amp_uav_ch%d',kk)) = amp_uav(kk);
        end

        row.mean_snr_uav = mean_snr_uav;
        row.min_snr_uav = min_snr_uav;
        row.mean_peak_uav = mean_peak_uav;
        row.min_peak_uav = min_peak_uav;
        row.mean_toa_conf_uav = mean_conf_uav;
        row.min_toa_conf_uav = min_conf_uav;
        row.valid_tdoa_count = valid_tdoa_count;
        row.observation_quality_score = observation_quality_score;
        row.observation_quality_class = observation_quality_class;

        row.uav_rel_x = uavRel(1);
        row.uav_rel_y = uavRel(2);
        row.gn_est_rel_x = gnEstRel(1);
        row.gn_est_rel_y = gnEstRel(2);
        row.gn_err_x = gnErr(1);
        row.gn_err_y = gnErr(2);
        row.gn_pos_err_m = norm(gnErr);
        row.ctekf_est_rel_x = ekfEstRel(1);
        row.ctekf_est_rel_y = ekfEstRel(2);
        row.ctekf_err_x = ekfErr(1);
        row.ctekf_err_y = ekfErr(2);
        row.ctekf_pos_err_m = ekfErr_m;
        row.ctekf_speed_mps = ekfState(3);
        row.ctekf_heading_rad = ekfState(4);
        row.ctekf_turn_rate_radps = ekfState(5);
        row.ctekf_reset_flag = double(ekfWasReset);
        row.ekf_to_gn_dist_m = ekfToGnDist;

        row.ref_abs_x = refPos(1);
        row.ref_abs_y = refPos(2);
        row.uav_abs_x = uavAbs(1);
        row.uav_abs_y = uavAbs(2);
        row.gn_abs_x = gnEstAbs(1);
        row.gn_abs_y = gnEstAbs(2);
        row.ctekf_abs_x = ekfEstAbs(1);
        row.ctekf_abs_y = ekfEstAbs(2);

        row.noise_power = noisePower;
        row.tx_offset_ch1_ns = txTimingOffset_ns(1);
        row.tx_offset_ch2_ns = txTimingOffset_ns(2);
        row.tx_offset_ch3_ns = txTimingOffset_ns(3);
        row.tx_offset_ch4_ns = txTimingOffset_ns(4);
        row.master_waveform_id = master_waveform_id_val;

        localRowCells{imeas} = row;

        scenarioMeanSnr(imeas) = mean_snr_uav;
        scenarioValidCount(imeas) = valid_tdoa_count;
        scenarioObsQuality(imeas) = observation_quality_score;
    end

    %% Scenario summary

    meanGNError = mean(results(:,6));
    meanEKFError = mean(ekfResults(:,4));
    maxGNError = max(results(:,6));
    maxEKFError = max(ekfResults(:,4));
    improvement_m = meanGNError - meanEKFError;
    improvement_percent = 100 * improvement_m / max(meanGNError, eps);

    fprintf('Scenario %d | Mean GN localization error     : %.4f m\n', iscenario, meanGNError);
    fprintf('Scenario %d | Mean CT-EKF localization error : %.4f m\n', iscenario, meanEKFError);
    fprintf('Scenario %d | CT-EKF improvement             : %.4f m | %.2f %%\n', ...
        iscenario, improvement_m, improvement_percent);

    summary = summaryTemplate;
    summary.scenario_id = iscenario;
    summary.numMeas = numMeas;
    summary.motion_type = string(motionType);
    summary.motion_code = motion_type_to_code(motionType);
    summary.mean_gn_pos_err_m = meanGNError;
    summary.max_gn_pos_err_m = maxGNError;
    summary.mean_ctekf_pos_err_m = meanEKFError;
    summary.max_ctekf_pos_err_m = maxEKFError;
    summary.ctekf_improvement_m = improvement_m;
    summary.ctekf_improvement_percent = improvement_percent;
    summary.mean_delta_err_ns = mean(results(:,7));
    summary.mean_geometry_score_true = mean(results(:,11));
    summary.mean_gdop_like_true = mean(results(:,12));
    summary.mean_condition_number_true = mean(results(:,13));
    summary.mean_uav_snr_dB = mean(scenarioMeanSnr);
    summary.mean_valid_tdoa_count = mean(scenarioValidCount);
    summary.mean_observation_quality_score = mean(scenarioObsQuality);
    summary.ekf_reset_count = tracker.resetCount;

    summary.tx1_x = txPos(1,1); summary.tx1_y = txPos(1,2);
    summary.tx2_x = txPos(2,1); summary.tx2_y = txPos(2,2);
    summary.tx3_x = txPos(3,1); summary.tx3_y = txPos(3,2);
    summary.tx4_x = txPos(4,1); summary.tx4_y = txPos(4,2);
    summary.ref_x = refPos(1); summary.ref_y = refPos(2);
    summary.uav_center_x = uavCenter(1); summary.uav_center_y = uavCenter(2);
    summary.uav_path_scale = uavScale;
    summary.startDeg = startDeg;
    summary.clockwise = double(clockwise);
    summary.noise_power = noisePower;
    summary.tx_offset_ch1_ns = txTimingOffset_ns(1);
    summary.tx_offset_ch2_ns = txTimingOffset_ns(2);
    summary.tx_offset_ch3_ns = txTimingOffset_ns(3);
    summary.tx_offset_ch4_ns = txTimingOffset_ns(4);

    scenarioRows = vertcat(localRowCells{:});
end
