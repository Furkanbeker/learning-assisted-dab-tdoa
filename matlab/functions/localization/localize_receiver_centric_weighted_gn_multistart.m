function [xHat, info] = localize_receiver_centric_weighted_gn_multistart( ...
    txPos, refPos, deltaTau_s, c, x0, weights, validMask, areaMin, areaMax)
    % LOCALIZE_RECEIVER_CENTRIC_WEIGHTED_GN_MULTISTART  Multi-start weighted GN
    % for receiver-centric TDOA.
    %
    % A single start can converge to a wrong hyperbolic branch far outside
    % the field. The best start is chosen from residuals and field limits.

    areaSpan = areaMax - areaMin;
    fieldCenter = [areaMin + 0.5*areaSpan, areaMin + 0.5*areaSpan];

    startList = [];
    startList = add_start_candidate(startList, x0(:).');
    startList = add_start_candidate(startList, mean(txPos,1));
    startList = add_start_candidate(startList, fieldCenter);
    startList = add_start_candidate(startList, refPos(:).');

    % Local starts around x0 (previous CT-EKF output).
    localStep = 0.08 * areaSpan;
    x0Local = x0(:).';
    localOffsets = [ ...
        0 0; 1 0; -1 0; 0 1; 0 -1; ...
        1 1; 1 -1; -1 1; -1 -1] * localStep;
    for iiLocal = 1:size(localOffsets,1)
        pLocal = x0Local + localOffsets(iiLocal,:);
        pLocal(1) = min(max(pLocal(1), areaMin), areaMax);
        pLocal(2) = min(max(pLocal(2), areaMin), areaMax);
        startList = add_start_candidate(startList, pLocal);
    end

    % Coarse 5 x 5 grid over the field.
    g = linspace(areaMin + 0.12*areaSpan, areaMax - 0.12*areaSpan, 5);
    for ix = 1:numel(g)
        for iy = 1:numel(g)
            startList = add_start_candidate(startList, [g(ix), g(iy)]);
        end
    end

    % Starts near each TX and between the TX centroid and REF.
    for k = 1:size(txPos,1)
        startList = add_start_candidate(startList, 0.70*txPos(k,:) + 0.30*fieldCenter);
    end
    startList = add_start_candidate(startList, 0.50*mean(txPos,1) + 0.50*refPos(:).');

    nStarts = size(startList,1);
    candidates = repmat(struct( ...
        'x', [NaN NaN], ...
        'score', inf, ...
        'rawRmsNs', inf, ...
        'weightedRmsNs', inf, ...
        'outsideDist', inf, ...
        'start', [NaN NaN], ...
        'singleInfo', struct()), nStarts, 1);

    bestIdx = 1;
    bestScore = inf;

    for sidx = 1:nStarts
        startPoint = startList(sidx,:);

        [candX, candInfo] = localize_receiver_centric_weighted_gn_single( ...
            txPos, refPos, deltaTau_s, c, startPoint, weights, validMask);

        [score, rawRmsNs, weightedRmsNs, outsideDist] = score_gn_candidate( ...
            candX, candInfo, areaMin, areaMax);

        candidates(sidx).x = candX;
        candidates(sidx).score = score;
        candidates(sidx).rawRmsNs = rawRmsNs;
        candidates(sidx).weightedRmsNs = weightedRmsNs;
        candidates(sidx).outsideDist = outsideDist;
        candidates(sidx).start = startPoint;
        candidates(sidx).singleInfo = candInfo;

        if score < bestScore
            bestScore = score;
            bestIdx = sidx;
        end
    end

    % Prefer candidates inside [areaMin, areaMax]^2; outside-field results
    % are treated as wrong branches.
    outsideVals = reshape([candidates.outsideDist], [], 1);
    scoreVals = reshape([candidates.score], [], 1);
    insideIdx = find(isfinite(scoreVals) & outsideVals <= 1e-6);

    if ~isempty(insideIdx)
        [~, locBestInside] = min(scoreVals(insideIdx));
        bestIdx = insideIdx(locBestInside);
    else
        [~, bestIdx] = min(scoreVals + 1000 * outsideVals);
        candidates(bestIdx).x(1) = min(max(candidates(bestIdx).x(1), areaMin), areaMax);
        candidates(bestIdx).x(2) = min(max(candidates(bestIdx).x(2), areaMin), areaMax);
        candidates(bestIdx).outsideDist = 0;
    end

    xHat = candidates(bestIdx).x;
    info = candidates(bestIdx).singleInfo;
    info.multistart_used = true;
    info.multistart_best_idx = bestIdx;
    info.multistart_num_starts = nStarts;
    info.multistart_score = candidates(bestIdx).score;
    info.raw_rms_ns = candidates(bestIdx).rawRmsNs;
    info.weighted_rms_ns = candidates(bestIdx).weightedRmsNs;
    info.outside_field_dist_m = candidates(bestIdx).outsideDist;
    info.best_start = candidates(bestIdx).start;

    % Per-candidate diagnostics.
    info.candidate_scores = reshape([candidates.score], [], 1);
    info.candidate_raw_rms_ns = reshape([candidates.rawRmsNs], [], 1);
    info.candidate_outside_dist_m = reshape([candidates.outsideDist], [], 1);
end


% --------------------------------------------------------------------
%  Local helper
%  -------------------------------------------------------------------

function startList = add_start_candidate(startList, p)
    % Append p to the GN start list unless it is invalid or duplicates an
    % existing start (within 1 m).

    p = p(:).';
    if numel(p) ~= 2 || any(~isfinite(p))
        return;
    end

    if isempty(startList)
        startList = p;
        return;
    end

    d = sqrt(sum((startList - p).^2, 2));
    if all(d > 1.0)
        startList = [startList; p]; %#ok<AGROW>
    end
end


% --------------------------------------------------------------------
%  Local helper
%  -------------------------------------------------------------------

function [score, rawRmsNs, weightedRmsNs, outsideDist] = score_gn_candidate( ...
    xHat, gnInfo, areaMin, areaMax)
    % Score a GN candidate (lower is better) from its TDOA residuals and its
    % distance outside the operating field.

    xHat = xHat(:).';

    if any(~isfinite(xHat))
        score = inf;
        rawRmsNs = inf;
        weightedRmsNs = inf;
        outsideDist = inf;
        return;
    end

    if isfield(gnInfo, 'raw_rms_ns') && ~isempty(gnInfo.raw_rms_ns)
        rawRmsNs = gnInfo.raw_rms_ns;
    else
        rawRmsNs = inf;
    end

    if isfield(gnInfo, 'weighted_rms_ns') && ~isempty(gnInfo.weighted_rms_ns)
        weightedRmsNs = gnInfo.weighted_rms_ns;
    else
        weightedRmsNs = rawRmsNs;
    end

    dxLow  = max(areaMin - xHat(1), 0);
    dxHigh = max(xHat(1) - areaMax, 0);
    dyLow  = max(areaMin - xHat(2), 0);
    dyHigh = max(xHat(2) - areaMax, 0);
    outsideDist = hypot(dxLow + dxHigh, dyLow + dyHigh);

    % Residual dominates; the field penalty separates outside-field branches.
    fieldPenaltyNs = 250.0 * outsideDist;
    score = rawRmsNs + 0.10 * weightedRmsNs + fieldPenaltyNs;
end
