function [x, P] = ct_ekf_step(x, P, z, dt, geometry_score, gdop_like, condition_number, measurementQuality, maneuverScore)
    % CT_EKF_STEP  One CT-EKF predict/update step with a GN position fix.
    %
    % State x = [px; py; v; psi; omega] (m, m, m/s, rad, rad/s).
    % Q grows with the maneuver score; R grows with poor geometry and low
    % PRS quality and is inflated when the chi-square gate fails.

    maneuverScore = clip01(maneuverScore);

    qPosScale     = 1 + 7.0  * maneuverScore;
    qSpeedScale   = 1 + 12.0 * maneuverScore;
    qHeadingScale = 1 + 16.0 * maneuverScore;
    qTurnScale    = 1 + 22.0 * maneuverScore;

    Q = diag([ ...
        (5^2)          * qPosScale, ...
        (5^2)          * qPosScale, ...
        (3^2)          * qSpeedScale, ...
        (deg2rad(6)^2) * qHeadingScale, ...
        (0.08^2)       * qTurnScale ...
    ]);

    baseR = 14^2;

    geomFactor = 1 / max(geometry_score, 0.05);
    gdopFactor = 1 + 0.35 * gdop_like;
    condFactor = 1 + 0.15 * max(0, condition_number - 2);

    qualityFactor = 1 / max(measurementQuality, 0.10);

    Rscale = geomFactor * gdopFactor * condFactor * qualityFactor;
    Rscale = min(max(Rscale, 1), 20);

    % Cap R during maneuvers with good PRS quality to avoid over-smoothing.
    if maneuverScore > 0.25 && measurementQuality > 0.50
        Rscale = min(Rscale, 3.5);
    end

    R = baseR * Rscale * eye(2);

    [xPred, F] = ct_predict_with_jacobian(x, dt);

    PPred = F * P * F.' + Q;

    H = [ ...
        1 0 0 0 0;
        0 1 0 0 0 ...
    ];

    zPred = H * xPred;
    innov = z(:) - zPred;

    S = H * PPred * H.' + R;

    gateValue = innov.' / S * innov;

    % Chi-square, 2 DOF: 9.21 is the 99% threshold.
    if maneuverScore > 0.35 && measurementQuality > 0.50
        gateThreshold = 16.0;
    else
        gateThreshold = 9.21;
    end

    if gateValue > gateThreshold
        if maneuverScore > 0.35 && measurementQuality > 0.50
            inflate = 1 + min(3, 0.25 * (gateValue / gateThreshold - 1));
        else
            inflate = min(50, gateValue / gateThreshold);
        end

        R = R * inflate;
        S = H * PPred * H.' + R;
    end

    K = PPred * H.' / S;

    x = xPred + K * innov;

    % Physical limits of the motion model.
    x(3) = max(0, min(150, x(3)));       % speed limit: 0 to 150 m/s
    x(5) = max(-0.8, min(0.8, x(5)));    % turn-rate limit: -0.8 to 0.8 rad/s

    I = eye(size(P));
    P = (I - K * H) * PPred * (I - K * H).' + K * R * K.';

    x(4) = wrapToPi_local(x(4));
end
