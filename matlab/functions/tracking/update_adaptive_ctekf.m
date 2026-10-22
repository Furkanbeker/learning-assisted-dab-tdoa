function [tracker, ekfPos, ekfToGnDist, ekfWasReset] = update_adaptive_ctekf( ...
    tracker, imeas, xHat, gnInfo, validTdoa, tdoaWeights, toaConfVals, ...
    geometry_score_est, gdopEstInfo, txGeomInfo, refPos, areaMin, areaMax, measDt)
    % UPDATE_ADAPTIVE_CTEKF  One maneuver-adaptive CT-EKF step on a GN fix.
    % Unreliable GN fixes are skipped (predict only). Uses observable
    % quantities only.
    %
    % Inputs
    %   tracker  struct with fields state ([px; py; v; psi; omega]), P,
    %            prevGnPos, prevPrevGnPos and resetCount
    %   imeas    measurement index (1-based)
    %   xHat     1 x 2 GN position estimate
    %   gnInfo, validTdoa, tdoaWeights, toaConfVals, geometry_score_est,
    %   gdopEstInfo, txGeomInfo, refPos, areaMin, areaMax, measDt
    %            GN diagnostics, TDOA quality and scenario information
    %
    % Outputs
    %   tracker      updated tracker struct
    %   ekfPos       1 x 2 reported (blended) position
    %   ekfToGnDist  distance between the CT-EKF state and the GN fix (m)
    %   ekfWasReset  true if a soft reset was applied

    % Unpack the tracker state.
    ekfState      = tracker.state;
    ekfP          = tracker.P;
    prevGnPos     = tracker.prevGnPos;
    prevPrevGnPos = tracker.prevPrevGnPos;
    ekfResetCount = tracker.resetCount;

    zGN = xHat(:);
    measurementQuality = mean(toaConfVals(:,2));

    [gnReliable, gnReliabilityInfo] = assess_gn_observation_reliability( ...
        xHat, gnInfo, validTdoa, tdoaWeights, measurementQuality, ...
        geometry_score_est, gdopEstInfo, areaMin, areaMax, refPos, txGeomInfo);

    if gnReliable
        maneuverScore = compute_gn_maneuver_score( ...
            prevPrevGnPos, prevGnPos, zGN, measDt, measurementQuality);
    else
        maneuverScore = 0;
    end

    if imeas <= 2
        maneuverScore = 0;
    end

    % First step: initialize the CT-EKF state [px; py; v; psi; omega].
    % Second step: initialize speed and heading from two GN fixes.
    if imeas == 1
        if gnReliable
            initPos = zGN(1:2);
        else
            initPos = xHat(:);
            initPos = min(max(initPos, [areaMin; areaMin]), [areaMax; areaMax]);
            if any(~isfinite(initPos)) || ~gnReliabilityInfo.insideSoftField
                initPos = txGeomInfo.centroid(:);
            end
        end

        ekfState = [initPos(1); initPos(2); 0; 0; 0];
        ekfP = diag([180^2, 180^2, 60^2, deg2rad(120)^2, 0.8^2]);
    else
        if gnReliable
            if imeas == 2 && ~isempty(prevGnPos)
                dPos = zGN(:) - prevGnPos(:);
                initSpeed = norm(dPos) / measDt;

                if initSpeed < 1e-6
                    initHeading = ekfState(4);
                else
                    initHeading = atan2(dPos(2), dPos(1));
                end

                ekfState(3) = min(initSpeed, 150);
                ekfState(4) = initHeading;
                ekfState(5) = 0;
            end

            [ekfState, ekfP] = ct_ekf_step( ...
                ekfState, ekfP, zGN, measDt, ...
                geometry_score_est, gdopEstInfo.gdop_like, ...
                gdopEstInfo.condition_number, measurementQuality, maneuverScore);
        else
            [ekfState, ekfP] = ct_ekf_predict_only_step(ekfState, ekfP, measDt);
        end
    end

    % Soft reset when the CT-EKF drifts too far from a reliable GN fix.
    ekfToGnDist = norm(ekfState(1:2).' - xHat);
    ekfWasReset = false;

    softResetThr = 20 ...
        + 35 * (1 - clip01(measurementQuality)) ...
        + 15 * (1 - clip01(geometry_score_est));

    resetAllowed = gnReliable && imeas > 3 && ...
        (measurementQuality > 0.35 || maneuverScore > 0.25 || ekfToGnDist > 45);

    if ekfToGnDist > softResetThr && resetAllowed
        pullToGn = 0.55 ...
            + 0.20 * clip01(measurementQuality) ...
            + 0.20 * clip01(maneuverScore) ...
            + 0.05 * clip01((ekfToGnDist - softResetThr) / 40);
        pullToGn = min(max(pullToGn, 0.55), 0.85);

        ekfState(1:2) = (1 - pullToGn) * ekfState(1:2) + pullToGn * zGN(1:2);

        if ~isempty(prevGnPos)
            dPosReset = zGN(:) - prevGnPos(:);
            resetSpeed = norm(dPosReset) / measDt;
            if resetSpeed > 1e-6
                ekfState(3) = min(resetSpeed, 150);
                ekfState(4) = atan2(dPosReset(2), dPosReset(1));
            else
                ekfState(3) = min(ekfState(3), 100);
            end
        else
            ekfState(3) = min(ekfState(3), 100);
        end

        if maneuverScore > 0.35
            ekfState(5) = 0.5 * ekfState(5);
        else
            ekfState(5) = 0;
        end

        ekfP(1:2,1:2) = ekfP(1:2,1:2) + 55^2 * eye(2);
        ekfResetCount = ekfResetCount + 1;
        ekfWasReset = true;
    end

    % Reported position: adaptive blend of the CT-EKF and GN estimates.
    if gnReliable
        alphaEKF = compute_adaptive_ekf_alpha( ...
            maneuverScore, measurementQuality, geometry_score_est, ekfToGnDist);

        ekfRawPos = ekfState(1:2).';
        ekfPos = alphaEKF * ekfRawPos + (1 - alphaEKF) * xHat;
    else
        alphaEKF = 1;
        ekfRawPos = ekfState(1:2).';
        ekfPos = ekfRawPos;
    end

    % The next prediction starts from the blended estimate.
    if gnReliable
        ekfState(1:2) = ekfPos(:);
    end

    if gnReliable
        if ~isempty(prevGnPos)
            prevPrevGnPos = prevGnPos;
        end
        prevGnPos = zGN;
    end

    % Pack the updated tracker state.
    tracker.state         = ekfState;
    tracker.P             = ekfP;
    tracker.prevGnPos     = prevGnPos;
    tracker.prevPrevGnPos = prevPrevGnPos;
    tracker.resetCount    = ekfResetCount;
end
