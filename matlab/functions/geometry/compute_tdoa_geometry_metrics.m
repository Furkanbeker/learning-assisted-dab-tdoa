function gdopInfo = compute_tdoa_geometry_metrics(txPos, refPos, uavPos)
    % COMPUTE_TDOA_GEOMETRY_METRICS  GDOP-like metric and condition number
    % at uavPos.
    %
    % With REF known, the Jacobian depends only on the TX-to-UAV unit
    % vectors, so refPos is unused.

    numTx = size(txPos,1);
    H = zeros(numTx,2);

    x = uavPos(:);

    for k = 1:numTx

        sk = txPos(k,:).';

        dk_uav = norm(x - sk);

        if dk_uav < 1e-9
            dk_uav = 1e-9;
        end

        H(k,1) = (x(1) - sk(1)) / dk_uav;
        H(k,2) = (x(2) - sk(2)) / dk_uav;
    end

    A = H' * H;

    if rcond(A) < 1e-12
        Q = pinv(A);
        condition_number = 1 / max(rcond(A), eps);
    else
        Q = inv(A);
        condition_number = cond(A);
    end

    gdop_like = sqrt(trace(Q));

    gdopInfo.H = H;
    gdopInfo.gdop_like = gdop_like;
    gdopInfo.condition_number = condition_number;
end
