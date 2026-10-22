function [tdoaWeights, validTdoa] = compute_tdoa_weights(toaConfVals, estDelta, maxExpectedDelta_s)
    % COMPUTE_TDOA_WEIGHTS  Weight and validity flag for each receiver-centric TDOA.
    %
    % Weight = geometric mean of the REF and UAV TOA confidences. Valid if
    % |TDOA| <= maxExpectedDelta_s and weight >= 0.10.
    %
    % Inputs
    %   toaConfVals        numTx x 2 TOA confidences (column 1 = REF, 2 = UAV)
    %   estDelta           1 x numTx estimated TDOAs (s)
    %   maxExpectedDelta_s largest physically possible |TDOA| (s)
    %
    % Outputs
    %   tdoaWeights  numTx x 1 weights in [0, 1]
    %   validTdoa    numTx x 1 logical validity flags

    numTx = size(toaConfVals, 1);

    tdoaWeights = zeros(numTx,1);
    validTdoa = false(numTx,1);

    for k = 1:numTx
        confRef = toaConfVals(k,1);
        confUav = toaConfVals(k,2);
        wTdoa = sqrt(max(confRef,0) * max(confUav,0));
        isPhysicallyValid = abs(estDelta(k)) <= maxExpectedDelta_s;
        isConfident = wTdoa >= 0.10;
        tdoaWeights(k) = wTdoa;
        validTdoa(k) = isPhysicallyValid && isConfident;
    end
end
