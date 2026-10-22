function p = sample_random_point_far_from_tx(txPos, areaMin, areaMax, minDistToTx, margin, maxTry)
    % SAMPLE_RANDOM_POINT_FAR_FROM_TX  Random REF position at least
    % minDistToTx from every TX.

    areaSpan = areaMax - areaMin;
    centroid = mean(txPos, 1);
    txGeomInfo = compute_tx_polygon_info(txPos);

    % REF is not forced inside the TX hull, but very distant REF positions
    % give ill-conditioned TDOA geometry and are rejected.
    maxRefCentroidDist = 0.72 * sqrt(2) * areaSpan;
    minRefGeomScore = 0.06;
    maxRefCond = 250;

    p = [];

    for ii = 1:maxTry
        cand = areaMin + margin + (areaSpan - 2*margin) * rand(1,2);
        dTx = sqrt(sum((txPos - cand).^2, 2));
        if any(dTx < minDistToTx)
            continue;
        end

        candInfo = compute_point_geometry_info(cand, txPos);
        candGdop = compute_tdoa_geometry_metrics(txPos, cand, cand);
        candScore = compute_geometry_score( ...
            candInfo.isInsideTxPolygon, candInfo.isInsideTxPolygon, ...
            candGdop.gdop_like, candGdop.condition_number, ...
            candInfo.pointToCentroidDist, candInfo.pointToCentroidDist, ...
            txGeomInfo.equivalentRadius);

        if norm(cand - centroid) <= maxRefCentroidDist && ...
           candScore >= minRefGeomScore && candGdop.condition_number <= maxRefCond
            p = cand;
            return;
        end
    end

    % Relaxed retry: TX distance check only (0.6 x minDistToTx).
    for ii = 1:maxTry
        cand = areaMin + margin + (areaSpan - 2*margin) * rand(1,2);
        dTx = sqrt(sum((txPos - cand).^2, 2));
        if all(dTx >= 0.6 * minDistToTx)
            p = cand;
            return;
        end
    end

    p = areaMin + margin + (areaSpan - 2*margin) * rand(1,2);
end
