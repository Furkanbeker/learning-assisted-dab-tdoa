function [path, centerPos, scaleValue] = generate_random_line_like_path( ...
    areaMin, areaMax, fieldMargin, u, v, halfLength0, amplitude0, cycles, numPts, t, envelopeMode)
    % GENERATE_RANDOM_LINE_LIKE_PATH  Straight or sinusoidal path along u
    % with lateral offset along v.
    %
    % amplitude0 = 0 or cycles = 0 gives a straight line. Length and
    % amplitude shrink until the path fits inside the field.

    if nargin < 11
        envelopeMode = "constant";
    end

    areaSpan = areaMax - areaMin;
    halfLength = halfLength0;
    amplitude = amplitude0;

    for rr = 1:180
        marginNeeded = fieldMargin + amplitude + 40;
        centerPos = sample_center_with_margin(areaMin, areaMax, marginNeeded);

        s = linspace(halfLength, -halfLength, numPts).';
        baseLine = centerPos + s.*u;

        if amplitude <= 0 || cycles <= 0
            offset = zeros(numPts,1);
        else
            if strcmpi(char(envelopeMode), 'contract_expand')
                % Amplitude large at both ends, small in the middle.
                envelope = 0.22 + 0.78 * abs(2*t - 1);
                envelope = smoothstep01(envelope);
            else
                envelope = ones(numPts,1);
            end
            offset = amplitude * envelope .* sin(2*pi*cycles*t);
        end

        path = baseLine + offset.*v;

        insidePath = all(path(:,1) >= areaMin + fieldMargin) && all(path(:,1) <= areaMax - fieldMargin) && ...
                     all(path(:,2) >= areaMin + fieldMargin) && all(path(:,2) <= areaMax - fieldMargin);
        if insidePath
            scaleValue = max(halfLength, amplitude);
            return;
        end

        halfLength = 0.97 * halfLength;
        amplitude = 0.95 * amplitude;

        if halfLength < 0.12 * areaSpan
            halfLength = 0.12 * areaSpan;
        end
    end

    % Fallback: shorter path near the field center.
    centerPos = [areaMin + 0.5*areaSpan, areaMin + 0.5*areaSpan] + 0.20*areaSpan*(rand(1,2)-0.5);
    halfLength = min(halfLength, 0.25*areaSpan);
    amplitude = min(amplitude, 0.06*areaSpan);
    s = linspace(halfLength, -halfLength, numPts).';
    baseLine = centerPos + s.*u;

    if amplitude <= 0 || cycles <= 0
        offset = zeros(numPts,1);
    else
        if strcmpi(char(envelopeMode), 'contract_expand')
            envelope = 0.22 + 0.78 * abs(2*t - 1);
            envelope = smoothstep01(envelope);
        else
            envelope = ones(numPts,1);
        end
        offset = amplitude * envelope .* sin(2*pi*cycles*t);
    end

    path = baseLine + offset.*v;
    path(:,1) = min(max(path(:,1), areaMin + fieldMargin), areaMax - fieldMargin);
    path(:,2) = min(max(path(:,2), areaMin + fieldMargin), areaMax - fieldMargin);
    centerPos = mean(path,1);
    scaleValue = max(halfLength, amplitude);
end
