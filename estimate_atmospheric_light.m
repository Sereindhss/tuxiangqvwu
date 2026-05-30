function A = estimate_atmospheric_light(I, dark, topPercent)
%ESTIMATE_ATMOSPHERIC_LIGHT Estimate atmospheric light using the dark channel.

    if nargin < 3 || isempty(topPercent)
        topPercent = 0.001;
    end

    I = im2double(I);
    flatDark = dark(:);
    n = numel(flatDark);
    nTop = max(1, round(n * topPercent));

    [~, order] = sort(flatDark, 'descend');
    candidates = order(1:nTop);

    flatI = reshape(I, [], 3);
    candidatePixels = flatI(candidates, :);
    [~, idx] = max(sum(candidatePixels, 2));
    A = candidatePixels(idx, :);
    A = max(A, 1e-6);
end
