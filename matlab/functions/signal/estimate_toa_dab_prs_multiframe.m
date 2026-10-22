function [tauHat_s, delayLagHat, peakVal, quality] = estimate_toa_dab_prs_multiframe(sig, prsTemplate, fs, prsSearchCenters, searchHalfLag)
    % ESTIMATE_TOA_DAB_PRS_MULTIFRAME  PRS-based TOA over up to 5 DAB frames.
    %
    % Matches the PRS template around each expected frame position, rejects
    % outlier frames (MAD test) and returns the quality-weighted median delay.

    sig = sig(:);
    prsTemplate = prsTemplate(:);
    prsSearchCenters = prsSearchCenters(:);

    L = length(prsTemplate);
    N = length(sig);

    validCenters = prsSearchCenters(prsSearchCenters >= 0 & prsSearchCenters + L - 1 <= N);
    if isempty(validCenters)
        error('No valid PRS search centers fit inside the received signal.');
    end

    maxFramesToUse = min(5, numel(validCenters));
    validCenters = validCenters(1:maxFramesToUse);

    delayEst = zeros(numel(validCenters),1);
    peakList = zeros(numel(validCenters),1);
    peakToMedianList = zeros(numel(validCenters),1);
    peakToSecondList = zeros(numel(validCenters),1);
    qualityList = zeros(numel(validCenters),1);

    for ii = 1:numel(validCenters)
        centerLag = validCenters(ii);

        [absLagHat, peakValThis, peakToMedian, peakToSecond] = ...
            estimate_template_matched_search_centered(sig, prsTemplate, centerLag, searchHalfLag);

        delayEst(ii) = absLagHat - centerLag;
        peakList(ii) = peakValThis;
        peakToMedianList(ii) = peakToMedian;
        peakToSecondList(ii) = peakToSecond;

        peakScore = clip01((peakValThis - 0.60) / 0.35);
        medianScore = clip01(log10(max(peakToMedian,1)) / log10(10));
        secondScore = clip01((peakToSecond - 1.00) / 0.20);
        qualityList(ii) = peakScore * (0.55 + 0.25*medianScore + 0.20*secondScore);
    end

    finiteMask = isfinite(delayEst) & isfinite(qualityList) & peakList > 0;
    delayEst = delayEst(finiteMask);
    peakList = peakList(finiteMask);
    peakToMedianList = peakToMedianList(finiteMask);
    peakToSecondList = peakToSecondList(finiteMask);
    qualityList = qualityList(finiteMask);

    if isempty(delayEst)
        delayLagHat = 0;
        peakVal = 0;
        tauHat_s = 0;
        quality = make_toa_quality(0, 1, 1, 0, 0, 0, 0);
        return;
    end

    % Keep high-quality frames first, then reject delay outliers.
    [~, ord] = sort(qualityList, 'descend');
    keepN = min(5, numel(ord));
    keep = ord(1:keepN);

    keptDelays = delayEst(keep);
    keptWeights = qualityList(keep) + eps;
    keptPeaks = peakList(keep);
    keptPeakToMedian = peakToMedianList(keep);
    keptPeakToSecond = peakToSecondList(keep);

    medDelay = median(keptDelays);
    madDelay = median(abs(keptDelays - medDelay)) + eps;

    % Inlier tolerance: 3 x MAD, at least 2 samples.
    inlier = abs(keptDelays - medDelay) <= max(3*madDelay, 2.0);

    if nnz(inlier) < 2 && numel(keptDelays) >= 2
        % Keep at least the two best detections.
        inlier = false(size(keptDelays));
        inlier(1:min(2,numel(keptDelays))) = true;
    end

    keptDelays = keptDelays(inlier);
    keptWeights = keptWeights(inlier);
    keptPeaks = keptPeaks(inlier);
    keptPeakToMedian = keptPeakToMedian(inlier);
    keptPeakToSecond = keptPeakToSecond(inlier);

    delayLagHat = weighted_median(keptDelays, keptWeights);
    peakVal = max(keptPeaks);
    tauHat_s = delayLagHat / fs;

    frameStd = std(keptDelays);
    frameConsistency = clip01(1 - frameStd / max(searchHalfLag,1));

    meanPeak = mean(keptPeaks);
    meanPeakToMedian = mean(keptPeakToMedian);
    meanPeakToSecond = mean(keptPeakToSecond);

    peakScore = clip01((meanPeak - 0.60) / 0.35);
    medianScore = clip01(log10(max(meanPeakToMedian,1)) / log10(10));
    secondScore = clip01((meanPeakToSecond - 1.00) / 0.20);

    confidence = clip01(0.45*peakScore + 0.25*medianScore + 0.15*secondScore + 0.15*frameConsistency);

    quality = make_toa_quality( ...
        confidence, meanPeakToMedian, meanPeakToSecond, frameConsistency, ...
        numel(keptDelays), meanPeak, frameStd);
end


% --------------------------------------------------------------------
%  Local helper
%  -------------------------------------------------------------------

function q = make_toa_quality(confidence, peakToMedian, peakToSecond, frameConsistency, numFramesUsed, meanPeak, frameStdSamples)
    % Pack the TOA quality metrics into a struct.
    q = struct();
    q.confidence = confidence;
    q.peakToMedian = peakToMedian;
    q.peakToSecond = peakToSecond;
    q.frameConsistency = frameConsistency;
    q.numFramesUsed = numFramesUsed;
    q.meanPeak = meanPeak;
    q.frameStdSamples = frameStdSamples;
end
