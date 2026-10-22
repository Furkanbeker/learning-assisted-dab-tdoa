function [trainSc, valSc, testSc, splitLabel] = split_scenarios(scenarioIds, splitSeed)
    % SPLIT_SCENARIOS  Scenario-wise 70 / 15 / 15 train / val / test split.
    %
    % All measurements of a scenario go to the same subset.
    %
    % Inputs
    %   scenarioIds  scenario ID of every dataset row (column vector)
    %   splitSeed    random seed of the split
    %
    % Outputs
    %   trainSc, valSc, testSc  scenario IDs in each subset
    %   splitLabel              "train" / "val" / "test" for every row

    allScenarios = unique(scenarioIds);
    numScenarioTotal = numel(allScenarios);

    rng(splitSeed, 'twister');
    permSc = allScenarios(randperm(numScenarioTotal));

    nTrain = round(0.70 * numScenarioTotal);
    nVal   = round(0.15 * numScenarioTotal);

    trainSc = permSc(1:nTrain);
    valSc   = permSc(nTrain+1 : nTrain+nVal);
    testSc  = permSc(nTrain+nVal+1 : end);

    splitLabel = strings(numel(scenarioIds), 1);
    splitLabel(ismember(scenarioIds, trainSc)) = "train";
    splitLabel(ismember(scenarioIds, valSc))   = "val";
    splitLabel(ismember(scenarioIds, testSc))  = "test";
end
