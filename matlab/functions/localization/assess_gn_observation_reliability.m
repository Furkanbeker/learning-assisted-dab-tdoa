function [isReliable, info] = assess_gn_observation_reliability( ...
    xHat, gnInfo, validTdoa, tdoaWeights, measurementQuality, ...
    geometryScoreEst, gdopEstInfo, areaMin, areaMax, refPos, txGeomInfo)
    % ASSESS_GN_OBSERVATION_RELIABILITY  Decide whether a GN fix may update
    % the CT-EKF. Uses observable quantities only.

    areaSpan = areaMax - areaMin;
    % A fix far outside the field is usually a wrong hyperbolic branch.
    softMargin = 0.04 * areaSpan;

    xHat = xHat(:).';

    insideSoftField = all(isfinite(xHat)) && ...
        xHat(1) >= areaMin - softMargin && xHat(1) <= areaMax + softMargin && ...
        xHat(2) >= areaMin - softMargin && xHat(2) <= areaMax + softMargin;

    activeCount = nnz(validTdoa(:));
    if activeCount > 0
        meanActiveWeight = mean(tdoaWeights(validTdoa));
    else
        meanActiveWeight = 0;
    end

    if isfield(gnInfo, 'weighted_rms_ns') && ~isempty(gnInfo.weighted_rms_ns)
        finalWeightedResNs = gnInfo.weighted_rms_ns;
    elseif isfield(gnInfo, 'weighted_resnorm') && ~isempty(gnInfo.weighted_resnorm)
        finalWeightedResNs = gnInfo.weighted_resnorm(end) / sqrt(max(activeCount,1)) * 1e9;
    else
        finalWeightedResNs = inf;
    end

    if isfield(gnInfo, 'raw_rms_ns') && ~isempty(gnInfo.raw_rms_ns)
        finalRawResNs = gnInfo.raw_rms_ns;
    else
        finalRawResNs = finalWeightedResNs;
    end

    centroidDist = norm(xHat - txGeomInfo.centroid);
    refCentroidDist = norm(refPos - txGeomInfo.centroid);

    residualOK = finalWeightedResNs <= 700 && finalRawResNs <= 900;
    geometryOK = geometryScoreEst >= 0.10 && ...
                 gdopEstInfo.gdop_like <= 7.5 && ...
                 gdopEstInfo.condition_number <= 250;
    observableOK = activeCount >= 3 && ...
                   meanActiveWeight >= 0.08 && ...
                   measurementQuality >= 0.08;
    fieldOK = insideSoftField && ...
              centroidDist <= 1.05 * sqrt(2) * areaSpan && ...
              refCentroidDist <= 1.05 * sqrt(2) * areaSpan;

    isReliable = fieldOK && observableOK && geometryOK && residualOK;

    info = struct();
    info.insideSoftField = insideSoftField;
    info.activeCount = activeCount;
    info.meanActiveWeight = meanActiveWeight;
    info.finalWeightedResNs = finalWeightedResNs;
    info.finalRawResNs = finalRawResNs;
    info.geometryOK = geometryOK;
    info.observableOK = observableOK;
    info.fieldOK = fieldOK;
    info.residualOK = residualOK;
end
