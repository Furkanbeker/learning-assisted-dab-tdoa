function [lagHat, peakVal, peakToMedian, peakToSecond] = estimate_template_matched_search_centered(sig, template, centerLag, halfLag)
    % ESTIMATE_TEMPLATE_MATCHED_SEARCH_CENTERED  Normalized matched-filter
    % search in [centerLag - halfLag, centerLag + halfLag].
    %
    % Parabolic sub-sample peak refinement. Also returns peak-to-median and
    % peak-to-second-peak ratios.

    sig = sig(:);
    template = template(:);

    L = length(template);
    N = length(sig);

    lagMin = max(0, round(centerLag - halfLag));
    lagMax = min(N - L, round(centerLag + halfLag));

    assert(lagMax >= lagMin, 'Signal too short for centered TOA matched search.');

    lagGrid = (lagMin:lagMax).';

    tpl = template - mean(template);
    tplNorm = norm(tpl) + eps;

    % Vectorized over all lags in the search interval.
    searchSig = sig(lagMin + 1 : lagMax + L);

    numerator = conv(searchSig, flipud(conj(tpl)), 'valid');

    win = ones(L, 1);
    segSum = conv(searchSig, win, 'valid');
    segEnergy = conv(abs(searchSig).^2, win, 'valid');
    segZeroMeanEnergy = real(segEnergy - (abs(segSum).^2) ./ L);
    segZeroMeanEnergy = max(segZeroMeanEnergy, 0);
    segNorm = sqrt(segZeroMeanEnergy) + eps;

    metric = abs(numerator) ./ (tplNorm .* segNorm);
    metric = metric(:);

    [peakVal, idxMax] = max(metric);
    peakToMedian = peakVal / (median(metric) + eps);

    exclusion = max(3, round(0.02 * numel(metric)));
    secondMetric = metric;
    lo = max(1, idxMax - exclusion);
    hi = min(numel(metric), idxMax + exclusion);
    secondMetric(lo:hi) = -inf;
    secondPeak = max(secondMetric);
    if ~isfinite(secondPeak) || secondPeak <= 0
        secondPeak = median(metric) + eps;
    end
    peakToSecond = peakVal / (secondPeak + eps);

    lagInt = lagGrid(idxMax);
    lagFrac = 0;

    if idxMax > 1 && idxMax < length(metric)
        y1 = metric(idxMax-1);
        y2 = metric(idxMax);
        y3 = metric(idxMax+1);
        denom = (y1 - 2*y2 + y3);
        if abs(denom) > 1e-12
            lagFrac = 0.5 * (y1 - y3) / denom;
        end
    end

    lagHat = lagInt + lagFrac;
end
