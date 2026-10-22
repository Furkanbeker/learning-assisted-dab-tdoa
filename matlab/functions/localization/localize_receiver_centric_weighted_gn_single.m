function [xHat, info] = localize_receiver_centric_weighted_gn_single( ...
    txPos, refPos, deltaTau_s, c, x0, weights, validMask)
    % LOCALIZE_RECEIVER_CENTRIC_WEIGHTED_GN_SINGLE  Single-start weighted GN
    % for receiver-centric TDOA (called by the multi-start wrapper).

    deltaTau_s = deltaTau_s(:);
    weights = weights(:);
    validMask = validMask(:);

    numTx = size(txPos,1);

    if numel(weights) ~= numTx
        weights = ones(numTx,1);
    end
    if numel(validMask) ~= numTx
        validMask = true(numTx,1);
    end

    weights(~isfinite(weights) | weights < 0) = 0;
    validMask = validMask & isfinite(deltaTau_s) & isfinite(weights);

    if nnz(validMask) < 3
        [~, ord] = sort(weights, 'descend');
        validMask = false(numTx,1);
        validMask(ord(1:min(3,numTx))) = true;
    end

    activeIdx = find(validMask);
    if isempty(activeIdx)
        activeIdx = (1:numTx).';
        weights = ones(numTx,1);
    end

    x = x0(:);

    maxIter = 45;
    tol = 1e-6;

    info.resnorm = [];
    info.weighted_resnorm = [];
    info.raw_rms_ns_history = [];
    info.weighted_rms_ns_history = [];
    info.iter = 0;
    info.activeIdx = activeIdx;
    info.inputWeights = weights;
    info.validMask = validMask;

    lastRawR = inf(numel(activeIdx),1);
    lastWeightedR = inf(numel(activeIdx),1);

    for it = 1:maxIter

        h = zeros(numel(activeIdx),1);
        H = zeros(numel(activeIdx),2);
        y = deltaTau_s(activeIdx);
        w = weights(activeIdx);
        w = max(w, 1e-3);

        for ii = 1:numel(activeIdx)
            k = activeIdx(ii);
            sk = txPos(k,:).';

            dk_uav = norm(x - sk);
            dk_ref = norm(refPos(:) - sk);

            if dk_uav < 1e-12
                dk_uav = 1e-12;
            end

            h(ii) = (dk_uav - dk_ref) / c;
            H(ii,1) = (x(1) - sk(1)) / (c * dk_uav);
            H(ii,2) = (x(2) - sk(2)) / (c * dk_uav);
        end

        r = y - h;

        medAbs = median(abs(r - median(r))) + eps;
        huberK = max(3 * medAbs, 50e-9);
        huberW = min(1, huberK ./ (abs(r) + eps));

        wEff = w .* huberW;
        Wsqrt = sqrt(wEff(:));

        Hw = H .* Wsqrt;
        rw = r .* Wsqrt;

        A = Hw' * Hw;
        b = Hw' * rw;

        if rcond(A) < 1e-12
            dx = pinv(Hw) * rw;
        else
            dx = A \ b;
        end

        maxStep = 500;
        stepNorm = norm(dx);
        if stepNorm > maxStep
            dx = dx * (maxStep / stepNorm);
        end

        % Halve the step while the raw residual grows by more than 15 %.
        rawRmsBefore = sqrt(mean(r.^2));
        xTrial = x + dx;
        rawRmsAfter = compute_raw_tdoa_rms(txPos, refPos, deltaTau_s, c, xTrial, activeIdx);
        dampCount = 0;
        while rawRmsAfter > 1.15 * rawRmsBefore && dampCount < 6
            dx = 0.5 * dx;
            xTrial = x + dx;
            rawRmsAfter = compute_raw_tdoa_rms(txPos, refPos, deltaTau_s, c, xTrial, activeIdx);
            dampCount = dampCount + 1;
        end

        x = xTrial;

        lastRawR = r;
        lastWeightedR = rw;

        info.resnorm(end+1,1) = norm(r);
        info.weighted_resnorm(end+1,1) = norm(rw);
        info.raw_rms_ns_history(end+1,1) = sqrt(mean(r.^2)) * 1e9;
        info.weighted_rms_ns_history(end+1,1) = sqrt(mean(rw.^2)) * 1e9;
        info.iter = it;
        info.finalWeights = wEff;

        if norm(dx) < tol
            break;
        end
    end

    xHat = x(:).';

    finalRawR = compute_raw_tdoa_residual(txPos, refPos, deltaTau_s, c, xHat, activeIdx);
    finalWeightedR = lastWeightedR;
    if numel(finalWeightedR) ~= numel(finalRawR) || any(~isfinite(finalWeightedR))
        finalWeightedR = finalRawR;
    end

    info.raw_residual_s = finalRawR;
    info.raw_rms_ns = sqrt(mean(finalRawR.^2)) * 1e9;
    info.weighted_rms_ns = sqrt(mean(finalWeightedR.^2)) * 1e9;
end
