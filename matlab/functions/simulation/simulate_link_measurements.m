function links = simulate_link_measurements(txPos, rxPosAll, txTimingOffset_s, noisePower, cfg)
    % SIMULATE_LINK_MEASUREMENTS  Simulate all TX-RX links for one time step.
    %
    % Each link: geometric delay + TX offset, FSPL, AWGN, then PRS-based TOA.
    %
    % Inputs
    %   txPos            numTx x 2 TX positions (m)
    %   rxPosAll         numRx x 2 receiver positions (row 1 = REF, row 2 = UAV)
    %   txTimingOffset_s 1 x numTx TX timing offsets (s)
    %   noisePower       AWGN power (normalized units)
    %   cfg              configuration struct (see generate_dab_tdoa_dataset.m)
    %
    % Output
    %   links  struct of numTx x numRx matrices: tauTrue, tauHat, peakVals,
    %          toaConfVals, peakToMedianVals, peakToSecondVals, snrVals,
    %          distanceVals, ampVals

    masterIQ      = cfg.masterIQ;
    txFreqHz      = cfg.txFreqHz;
    c             = cfg.c;
    fs            = cfg.fs;
    rxKeepLen     = cfg.rxKeepLen;
    template      = cfg.template;
    dabTimingInfo = cfg.dabTimingInfo;
    searchMaxLag  = cfg.searchMaxLag;

    numTx = size(txPos, 1);
    numRx = size(rxPosAll, 1);

    tauTrue = zeros(numTx, numRx);
    tauHat = zeros(numTx, numRx);
    peakVals = zeros(numTx, numRx);
    toaConfVals = zeros(numTx, numRx);
    peakToMedianVals = zeros(numTx, numRx);
    peakToSecondVals = zeros(numTx, numRx);
    snrVals = zeros(numTx, numRx);
    distanceVals = zeros(numTx, numRx);
    ampVals = zeros(numTx, numRx);

    for k = 1:numTx

        txWave = masterIQ;
        f = txFreqHz(k);

        for irx = 1:numRx

            rxPos = rxPosAll(irx,:);
            d = norm(rxPos - txPos(k,:));
            tau_geom = d / c;

            tau_total = tau_geom + txTimingOffset_s(k);
            delaySamples = tau_total * fs;

            % Free-space path loss with unit (0 dB) transmit power.
            lambda = c / f;
            d_eff = max(d,1);
            PL_dB = 20*log10(4*pi*d_eff / lambda);
            Pt_dB = 0;
            Pr_dB = Pt_dB - PL_dB;
            amp_fspl = 10^(Pr_dB/20);

            [ysig, chOut] = apply_minimal_dab_channel( ...
                txWave, delaySamples, rxKeepLen, amp_fspl, noisePower);

            [tauHat_s, lagHat, peakVal, toaQuality] = estimate_toa_dab_prs_multiframe( ...
                ysig, template, fs, dabTimingInfo.prsSearchCenters, searchMaxLag);

            tauTrue(k, irx) = tau_total;
            tauHat(k, irx) = tauHat_s;
            peakVals(k, irx) = peakVal;
            toaConfVals(k, irx) = toaQuality.confidence;
            peakToMedianVals(k, irx) = toaQuality.peakToMedian;
            peakToSecondVals(k, irx) = toaQuality.peakToSecond;
            snrVals(k, irx) = chOut.snr_dB;
            distanceVals(k, irx) = d;
            ampVals(k, irx) = amp_fspl;
        end
    end

    links = struct();
    links.tauTrue          = tauTrue;
    links.tauHat           = tauHat;
    links.peakVals         = peakVals;
    links.toaConfVals      = toaConfVals;
    links.peakToMedianVals = peakToMedianVals;
    links.peakToSecondVals = peakToSecondVals;
    links.snrVals          = snrVals;
    links.distanceVals     = distanceVals;
    links.ampVals          = ampVals;
end
