function q = guided_filter_gray(I, p, radius, epsVal)
%GUIDED_FILTER_GRAY Guided filter for grayscale guidance and input.

    if nargin < 3 || isempty(radius)
        radius = 40;
    end
    if nargin < 4 || isempty(epsVal)
        epsVal = 1e-3;
    end

    I = im2double(I);
    p = im2double(p);
    if ~isequal(size(I), size(p))
        error('Guided filter expects guidance and input to have the same size.');
    end

    win = 2 * radius + 1;
    kernel = ones(win, win);

    N = conv2(ones(size(I)), kernel, 'same');
    meanI = conv2(I, kernel, 'same') ./ N;
    meanP = conv2(p, kernel, 'same') ./ N;
    corrI = conv2(I .* I, kernel, 'same') ./ N;
    corrIp = conv2(I .* p, kernel, 'same') ./ N;

    varI = corrI - meanI .* meanI;
    covIp = corrIp - meanI .* meanP;

    a = covIp ./ (varI + epsVal);
    b = meanP - a .* meanI;

    meanA = conv2(a, kernel, 'same') ./ N;
    meanB = conv2(b, kernel, 'same') ./ N;

    q = meanA .* I + meanB;
    q = min(max(q, 0), 1);
end
