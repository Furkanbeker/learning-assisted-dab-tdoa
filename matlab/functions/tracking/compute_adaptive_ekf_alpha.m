function alphaEKF = compute_adaptive_ekf_alpha(maneuverScore, measurementQuality, geometryScore, ekfToGnDist)
    % COMPUTE_ADAPTIVE_EKF_ALPHA  Blending weight between CT-EKF and GN.
    %
    % Reported position = alphaEKF * EKF + (1 - alphaEKF) * GN.

    maneuverScore = clip01(maneuverScore);
    measurementQuality = clip01(measurementQuality);
    geometryScore = clip01(geometryScore);

    distPenalty = clip01((ekfToGnDist - 8) / 30);
    qualityBonus = clip01((measurementQuality - 0.55) / 0.45);
    geometryBonus = clip01((geometryScore - 0.45) / 0.55);

    % Lean toward GN during maneuvers or when the EKF drifts from GN,
    % so the filter does not lag behind curved paths.
    alphaEKF = 0.90 ...
        - 0.42 * maneuverScore ...
        - 0.28 * distPenalty ...
        + 0.05 * qualityBonus ...
        + 0.04 * geometryBonus;

    % Low maneuver and EKF consistent with GN: keep smoothing.
    if maneuverScore < 0.15 && ekfToGnDist < 14 && measurementQuality > 0.45
        alphaEKF = max(alphaEKF, 0.88);
    end

    % Maneuver with good PRS quality: let GN dominate.
    if maneuverScore > 0.30 && measurementQuality > 0.50
        alphaEKF = min(alphaEKF, 0.62);
    end

    if maneuverScore > 0.55 && measurementQuality > 0.50
        alphaEKF = min(alphaEKF, 0.48);
    end

    % Large EKF-GN gap with high PRS quality is usually model lag.
    if ekfToGnDist > 28 && measurementQuality > 0.60
        alphaEKF = min(alphaEKF, 0.45);
    end

    if ekfToGnDist > 45 && measurementQuality > 0.65
        alphaEKF = min(alphaEKF, 0.35);
    end

    if measurementQuality < 0.35
        alphaEKF = max(alphaEKF, 0.82);
    end

    alphaEKF = min(max(alphaEKF, 0.25), 0.97);
end
