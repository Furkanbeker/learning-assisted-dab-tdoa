function maneuverScore = compute_gn_maneuver_score(prevPrevGnPos, prevGnPos, zGN, dt, measurementQuality)
    % COMPUTE_GN_MANEUVER_SCORE  Maneuver indicator in [0, 1] from the last
    % three GN fixes.

    if isempty(prevPrevGnPos) || isempty(prevGnPos)
        maneuverScore = 0;
        return;
    end

    p0 = prevPrevGnPos(:);
    p1 = prevGnPos(:);
    p2 = zGN(:);

    vPrev = (p1 - p0) / max(dt, eps);
    vNow  = (p2 - p1) / max(dt, eps);

    speedPrev = norm(vPrev);
    speedNow  = norm(vNow);

    aObs = (vNow - vPrev) / max(dt, eps);
    accMag = norm(aObs);

    if speedPrev < 1e-6 || speedNow < 1e-6
        turnLike = 0;
    else
        hPrev = atan2(vPrev(2), vPrev(1));
        hNow  = atan2(vNow(2),  vNow(1));
        turnLike = abs(wrapToPi_local(hNow - hPrev)) / max(dt, eps);
    end

    speedChangeRatio = abs(speedNow - speedPrev) / max(max(speedPrev, speedNow), 1);

    accScore   = clip01((accMag - 2.0) / 10.0);
    turnScore  = clip01((turnLike - deg2rad(2)) / deg2rad(16));
    speedScore = clip01((speedChangeRatio - 0.08) / 0.35);

    maneuverScore = 0.50 * accScore + 0.35 * turnScore + 0.15 * speedScore;

    % With poor PRS quality, apparent maneuvers are mostly noise.
    qualityGate = clip01((measurementQuality - 0.25) / 0.45);
    maneuverScore = maneuverScore * qualityGate;

    maneuverScore = clip01(maneuverScore);
end
