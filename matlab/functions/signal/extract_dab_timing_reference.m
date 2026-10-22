function dabInfo = extract_dab_timing_reference(masterIQ, fs)
    % EXTRACT_DAB_TIMING_REFERENCE  Locate the Mode-I Null symbol and PRS in
    % the master waveform.
    %
    % Null candidates are validated by frame spacing; the useful part of the
    % following PRS is returned as the matched-filter template.

    x = masterIQ(:);
    p = abs(x).^2;

    assert(~isempty(x), 'masterIQ is empty.');

    % DAB Mode-I timing (sample counts at fs = 2.048 MHz).
    expectedNullLen = round(1.297e-3 * fs);      % Null symbol, 2656 samples
    guardLen        = round(246e-6  * fs);       % guard interval, 504 samples
    prsLen          = round(1.000e-3 * fs);      % useful symbol, 2048 samples
    frameLen        = round(96e-3   * fs);       % frame, 196608 samples

    N = length(x);
    assert(N > expectedNullLen + guardLen + prsLen, ...
        'masterIQ is too short for DAB timing extraction.');

    smoothLen = max(32, round(0.10e-3 * fs));
    pSmooth = movmean(p, smoothLen);

    hiPower = prctile(pSmooth, 90) + eps;
    activeThr = max(1e-12, 0.02 * hiPower);
    activeIdx = find(pSmooth > activeThr, 1, 'first');
    if isempty(activeIdx)
        activeIdx = 1;
    end

    step = 16;
    candStartGrid = (1:step:(N - expectedNullLen - guardLen - prsLen)).';
    nullEnergyGrid = zeros(numel(candStartGrid),1);
    postEnergyGrid = zeros(numel(candStartGrid),1);
    preEnergyGrid  = zeros(numel(candStartGrid),1);

    for ii = 1:numel(candStartGrid)
        s = candStartGrid(ii);
        eNull = s + expectedNullLen - 1;
        sPrsUseful = eNull + guardLen + 1;
        ePrsUseful = sPrsUseful + prsLen - 1;

        nullEnergyGrid(ii) = mean(pSmooth(s:eNull)) + eps;
        postEnergyGrid(ii) = mean(pSmooth(sPrsUseful:ePrsUseful)) + eps;

        preS = max(1, s - prsLen);
        preE = max(1, s - 1);
        if preE > preS
            preEnergyGrid(ii) = mean(pSmooth(preS:preE)) + eps;
        else
            preEnergyGrid(ii) = median(pSmooth) + eps;
        end
    end

    globalRefEnergy = median(pSmooth(pSmooth > activeThr));
    if isempty(globalRefEnergy) || ~isfinite(globalRefEnergy)
        globalRefEnergy = median(pSmooth) + eps;
    end

    nullLowScore  = globalRefEnergy ./ nullEnergyGrid;
    postRiseScore = postEnergyGrid ./ nullEnergyGrid;
    preRiseScore  = preEnergyGrid ./ nullEnergyGrid;

    startPenalty = ones(size(candStartGrid));
    startPenalty(candStartGrid < max(1, activeIdx - expectedNullLen)) = 0.35;

    rawScore = log10(nullLowScore + 1) + 1.5*log10(postRiseScore + 1) + 0.3*log10(preRiseScore + 1);
    rawScore = rawScore .* startPenalty;

    [~, order] = sort(rawScore, 'descend');
    selectedStarts = [];
    maxCandidates = min(40, numel(order));

    for ii = 1:numel(order)
        s = candStartGrid(order(ii));
        if isempty(selectedStarts) || all(abs(s - selectedStarts) > 0.45*frameLen)
            selectedStarts(end+1,1) = s;
        end
        if numel(selectedStarts) >= maxCandidates
            break;
        end
    end

    if isempty(selectedStarts)
        error('No DAB Null candidate could be detected.');
    end

    bestScore = -inf;
    bestNullStart = selectedStarts(1);
    bestFrameNullStarts = selectedStarts(1);

    for ii = 1:numel(selectedStarts)
        s0 = selectedStarts(ii);
        starts = s0;

        s = s0 - frameLen;
        while s >= 1
            starts = [s; starts];
            s = s - frameLen;
        end

        s = s0 + frameLen;
        while s + expectedNullLen + guardLen + prsLen - 1 <= N
            starts = [starts; s];
            s = s + frameLen;
        end

        validStarts = [];
        validScores = [];

        for jj = 1:numel(starts)
            ss = round(starts(jj));
            if ss < 1 || ss + expectedNullLen + guardLen + prsLen - 1 > N
                continue;
            end

            nullE = mean(pSmooth(ss:ss+expectedNullLen-1)) + eps;
            prsS = ss + expectedNullLen + guardLen;
            postE = mean(pSmooth(prsS:prsS+prsLen-1)) + eps;
            ratio = postE / nullE;

            if ratio > 2.0 || nullE < 0.35*globalRefEnergy
                validStarts(end+1,1) = ss;
                validScores(end+1,1) = log10(globalRefEnergy/nullE + 1) + log10(ratio + 1);
            end
        end

        if isempty(validStarts)
            continue;
        end

        candidateScore = mean(validScores) + 0.75*numel(validStarts);

        if s0 <= step && numel(validStarts) < 2
            candidateScore = candidateScore - 3;
        end

        if candidateScore > bestScore
            bestScore = candidateScore;
            bestNullStart = validStarts(1);
            bestFrameNullStarts = validStarts;
        end
    end

    nullStart = round(bestNullStart);
    nullEnd = nullStart + expectedNullLen - 1;
    frameNullStarts = round(bestFrameNullStarts(:));

    if isempty(frameNullStarts)
        frameNullStarts = nullStart;
    end

    prsStarts = frameNullStarts + expectedNullLen + guardLen;
    validPrsMask = prsStarts >= 1 & (prsStarts + prsLen - 1) <= N;
    prsStarts = prsStarts(validPrsMask);
    frameNullStarts = frameNullStarts(validPrsMask);

    if isempty(prsStarts)
        error('No valid DAB PRS/useful-symbol region found after Null detection.');
    end

    prsStart = prsStarts(1);
    prsTemplate = x(prsStart : prsStart + prsLen - 1);
    prsTemplate = prsTemplate - mean(prsTemplate);
    prsTemplate = prsTemplate / (norm(prsTemplate) + eps);

    prsConsistency = NaN;
    if numel(prsStarts) >= 2
        cc = zeros(numel(prsStarts),1);
        for ii = 1:numel(prsStarts)
            seg = x(prsStarts(ii):prsStarts(ii)+prsLen-1);
            seg = seg - mean(seg);
            cc(ii) = abs(prsTemplate' * seg) / ((norm(prsTemplate)+eps)*(norm(seg)+eps));
        end
        prsConsistency = median(cc);
    end

    nullEnergy = mean(p(max(1,nullStart):min(length(p),nullEnd))) + eps;
    signalEnergy = median(p(p > activeThr)) + eps;
    if isempty(signalEnergy) || ~isfinite(signalEnergy)
        signalEnergy = median(p) + eps;
    end
    nullEnergyRatio = nullEnergy / signalEnergy;

    dabInfo.nullStart = nullStart;
    dabInfo.nullEnd = nullEnd;
    dabInfo.prsStart = prsStart;
    dabInfo.prsLen = prsLen;
    dabInfo.guardLen = guardLen;
    dabInfo.expectedNullLen = expectedNullLen;
    dabInfo.frameLen = frameLen;
    dabInfo.frameNullStarts = frameNullStarts;
    dabInfo.prsStarts = prsStarts;
    dabInfo.prsSearchCenters = prsStarts - 1;
    dabInfo.prsTemplate = prsTemplate;
    dabInfo.nullEnergyRatio = nullEnergyRatio;
    dabInfo.prsConsistency = prsConsistency;
end
