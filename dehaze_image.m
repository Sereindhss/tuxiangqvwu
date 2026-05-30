function [J, info] = dehaze_image(I, opts)
%DEHAZE_IMAGE Dehaze a single image using dark channel prior.

    if nargin < 2
        opts = struct();
    end
    opts = fill_defaults(opts);

    I = im2double(I);
    if ndims(I) == 2
        I = repmat(I, [1 1 3]);
    elseif size(I, 3) > 3
        I = I(:, :, 1:3);
    end

    dark = dark_channel(I, opts.patchSize);
    A = estimate_atmospheric_light(I, dark, opts.topPercent);

    A3 = reshape(max(A, 1e-6), [1 1 3]);
    Inorm = bsxfun(@rdivide, I, A3);
    t = 1 - opts.omega * dark_channel(Inorm, opts.patchSize);

    guide = rgb2gray(I);
    tRefined = guided_filter_gray(guide, t, opts.guidedRadius, opts.guidedEps);
    tRefined = min(max(tRefined, 0), 1);

    tUse = max(tRefined, opts.t0);

    J = zeros(size(I));
    for c = 1:3
        J(:, :, c) = (I(:, :, c) - A(c)) ./ tUse + A(c);
    end
    J = min(max(J, 0), 1);

    if opts.enhanceContrast
        J = enhance_contrast(J);
    end

    info = struct();
    info.A = A;
    info.darkChannel = dark;
    info.transmissionRaw = t;
    info.transmissionRefined = tRefined;
end

function opts = fill_defaults(opts)
    if ~isfield(opts, 'patchSize') || isempty(opts.patchSize)
        opts.patchSize = 15;
    end
    if ~isfield(opts, 'omega') || isempty(opts.omega)
        opts.omega = 0.95;
    end
    if ~isfield(opts, 't0') || isempty(opts.t0)
        opts.t0 = 0.10;
    end
    if ~isfield(opts, 'guidedRadius') || isempty(opts.guidedRadius)
        opts.guidedRadius = 40;
    end
    if ~isfield(opts, 'guidedEps') || isempty(opts.guidedEps)
        opts.guidedEps = 1e-3;
    end
    if ~isfield(opts, 'topPercent') || isempty(opts.topPercent)
        opts.topPercent = 0.001;
    end
    if ~isfield(opts, 'enhanceContrast') || isempty(opts.enhanceContrast)
        opts.enhanceContrast = false;
    end
    opts.patchSize = max(1, round(opts.patchSize));
    opts.omega = min(max(opts.omega, 0), 1);
    opts.t0 = min(max(opts.t0, 0.01), 0.5);
    opts.guidedRadius = max(1, round(opts.guidedRadius));
    opts.guidedEps = max(opts.guidedEps, 1e-6);
    opts.topPercent = min(max(opts.topPercent, 1e-4), 0.1);
    opts.enhanceContrast = logical(opts.enhanceContrast);
end

function J = enhance_contrast(J)
    hsvImg = rgb2hsv(J);
    hsvImg(:, :, 3) = stretch_channel(hsvImg(:, :, 3), 0.01, 0.99);
    J = hsv2rgb(hsvImg);
    J = min(max(J, 0), 1);
end

function out = stretch_channel(in, lowFrac, highFrac)
    values = sort(in(:));
    n = numel(values);
    lo = values(max(1, round(lowFrac * n)));
    hi = values(min(n, round(highFrac * n)));
    if hi <= lo
        out = in;
    else
        out = (in - lo) ./ (hi - lo);
    end
    out = min(max(out, 0), 1);
end
