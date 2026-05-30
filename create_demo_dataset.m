function demo = create_demo_dataset(rootDir)
%CREATE_DEMO_DATASET Generate a small built-in demo dataset.

    if nargin < 1 || isempty(rootDir)
        rootDir = fileparts(mfilename('fullpath'));
    end

    demo.rootDir = fullfile(rootDir, 'demo_data');
    demo.hazyDir = fullfile(demo.rootDir, 'hazy');
    demo.gtDir = fullfile(demo.rootDir, 'gt');

    if ~exist(demo.rootDir, 'dir')
        mkdir(demo.rootDir);
    end
    if ~exist(demo.hazyDir, 'dir')
        mkdir(demo.hazyDir);
    end
    if ~exist(demo.gtDir, 'dir')
        mkdir(demo.gtDir);
    end

    scenes = {@scene_landscape, @scene_city, @scene_objects};
    names = {'demo_01_landscape', 'demo_02_city', 'demo_03_objects'};
    atmospheres = [ ...
        0.85 0.88 0.93; ...
        0.83 0.85 0.88; ...
        0.80 0.83 0.86];
    betas = [1.05, 1.15, 1.00];

    for k = 1:numel(scenes)
        [clearImage, depthMap] = scenes{k}(480, 640);
        hazyImage = render_haze(clearImage, depthMap, atmospheres(k, :), betas(k));
        imwrite(clearImage, fullfile(demo.gtDir, [names{k} '.png']));
        imwrite(hazyImage, fullfile(demo.hazyDir, [names{k} '.png']));
    end
end

function [image, depth] = scene_landscape(h, w)
    [X, Y] = meshgrid(linspace(0, 1, w), linspace(0, 1, h));
    image = zeros(h, w, 3);
    depth = ones(h, w);

    skyTop = [0.23 0.44 0.72];
    skyBottom = [0.86 0.93 0.98];
    for c = 1:3
        image(:, :, c) = skyTop(c) * (1 - Y) + skyBottom(c) * Y;
    end

    sun = exp(-(((X - 0.78) / 0.045) .^ 2 + ((Y - 0.18) / 0.06) .^ 2));
    for c = 1:3
        image(:, :, c) = min(max(image(:, :, c) + 0.16 * sun, 0), 1);
    end

    mountain1 = inpolygon(X, Y, [0.00 0.16 0.34 0.48], [0.58 0.27 0.50 0.58]);
    mountain2 = inpolygon(X, Y, [0.28 0.46 0.66 0.82], [0.58 0.23 0.47 0.58]);
    mountain3 = inpolygon(X, Y, [0.70 0.84 1.00], [0.58 0.33 0.58]);

    image = tint_region(image, mountain1, [0.20 0.29 0.33]);
    image = tint_region(image, mountain2, [0.16 0.24 0.28]);
    image = tint_region(image, mountain3, [0.18 0.26 0.31]);
    depth(mountain1 | mountain2 | mountain3) = 0.72;

    field = Y > 0.57;
    for c = 1:3
        fieldColor = [0.11 0.44 0.16];
        image(:, :, c) = image(:, :, c) .* (~field) + (fieldColor(c) + 0.10 * (1 - Y)) .* field;
    end
    depth(field) = 0.30 + 0.15 * Y(field);

    road = inpolygon(X, Y, [0.42 0.58 0.72 0.30], [1.00 1.00 0.58 0.58]);
    roadColor = reshape([0.45 0.44 0.42], 1, 1, 3);
    image = tint_region(image, road, roadColor);
    depth(road) = 0.18;

    lane1 = inpolygon(X, Y, [0.49 0.51 0.53 0.50], [0.92 0.92 0.78 0.78]);
    lane2 = inpolygon(X, Y, [0.52 0.54 0.56 0.53], [0.78 0.78 0.67 0.67]);
    lane3 = inpolygon(X, Y, [0.55 0.57 0.59 0.56], [0.67 0.67 0.60 0.60]);
    image = tint_region(image, lane1 | lane2 | lane3, [0.96 0.94 0.78]);
    depth(lane1 | lane2 | lane3) = 0.12;

    treeMask = make_tree_line(X, Y, 0.06, 0.15, 0.60, 0.08, 7);
    image = tint_region(image, treeMask, [0.09 0.32 0.10]);
    depth(treeMask) = 0.25;
end

function [image, depth] = scene_city(h, w)
    [X, Y] = meshgrid(linspace(0, 1, w), linspace(0, 1, h));
    image = zeros(h, w, 3);
    depth = ones(h, w);

    skyTop = [0.20 0.30 0.48];
    skyBottom = [0.86 0.90 0.94];
    for c = 1:3
        image(:, :, c) = skyTop(c) * (1 - Y) + skyBottom(c) * Y;
    end

    glow = exp(-(((X - 0.52) / 0.18) .^ 2 + ((Y - 0.25) / 0.10) .^ 2));
    image = add_glow(image, glow, [0.95 0.83 0.62], 0.10);

    buildingXs = [0.02 0.14 0.27 0.38 0.51 0.64 0.76 0.86];
    buildingWidths = [0.10 0.09 0.11 0.08 0.10 0.09 0.10 0.12];
    buildingHeights = [0.42 0.54 0.48 0.60 0.44 0.56 0.50 0.40];
    colors = [ ...
        0.24 0.29 0.36; ...
        0.28 0.34 0.43; ...
        0.22 0.27 0.32; ...
        0.30 0.35 0.42];

    for i = 1:numel(buildingXs)
        left = buildingXs(i);
        right = left + buildingWidths(i);
        top = 1 - buildingHeights(i);
        mask = inpolygon(X, Y, [left right right left], [1 1 top top]);
        buildingColor = colors(mod(i - 1, size(colors, 1)) + 1, :);
        image = tint_region(image, mask, buildingColor);
        depth(mask) = 0.58 + 0.05 * mod(i, 3);

        [windowsMask, windowsDepth] = building_windows(X, Y, left, right, top);
        image = tint_region(image, windowsMask, [0.96 0.85 0.48]);
        depth(windowsMask) = windowsDepth(windowsMask);
    end

    road = inpolygon(X, Y, [0.20 0.80 1.00 0.00], [1.00 1.00 0.74 0.74]);
    image = tint_region(image, road, [0.18 0.18 0.20]);
    depth(road) = 0.16;

    centerLine = inpolygon(X, Y, [0.49 0.51 0.52 0.48], [1.00 1.00 0.78 0.78]);
    image = tint_region(image, centerLine, [0.97 0.90 0.55]);
    depth(centerLine) = 0.10;

    sidewalk = inpolygon(X, Y, [0.00 0.20 0.28 0.00], [1.00 1.00 0.74 0.74]);
    image = tint_region(image, sidewalk, [0.37 0.37 0.38]);
    depth(sidewalk) = 0.24;
end

function [image, depth] = scene_objects(h, w)
    [X, Y] = meshgrid(linspace(0, 1, w), linspace(0, 1, h));
    image = zeros(h, w, 3);
    depth = ones(h, w);

    baseTop = [0.97 0.96 0.92];
    baseBottom = [0.84 0.90 0.94];
    for c = 1:3
        image(:, :, c) = baseTop(c) * (1 - Y) + baseBottom(c) * Y;
    end

    shadow = exp(-(((X - 0.50) / 0.45) .^ 2 + ((Y - 0.74) / 0.10) .^ 2));
    image = add_glow(image, shadow, [0.72 0.77 0.80], 0.08);

    tableMask = inpolygon(X, Y, [0.05 0.95 0.88 0.12], [0.86 0.86 1.00 1.00]);
    image = tint_region(image, tableMask, [0.48 0.35 0.24]);
    depth(tableMask) = 0.24;

    object1 = disk_mask(X, Y, 0.28, 0.58, 0.11);
    object2 = disk_mask(X, Y, 0.52, 0.50, 0.15);
    object3 = disk_mask(X, Y, 0.74, 0.62, 0.10);
    image = tint_region(image, object1, [0.88 0.25 0.26]);
    image = tint_region(image, object2, [0.23 0.56 0.84]);
    image = tint_region(image, object3, [0.16 0.64 0.34]);
    depth(object1) = 0.48;
    depth(object2) = 0.62;
    depth(object3) = 0.42;

    cube = inpolygon(X, Y, [0.62 0.84 0.79 0.57], [0.88 0.88 0.68 0.68]);
    image = tint_region(image, cube, [0.86 0.73 0.22]);
    depth(cube) = 0.38;

    cubeTop = inpolygon(X, Y, [0.62 0.73 0.88 0.79], [0.68 0.58 0.66 0.76]);
    image = tint_region(image, cubeTop, [0.94 0.83 0.34]);
    depth(cubeTop) = 0.30;

    plantStem = inpolygon(X, Y, [0.15 0.18 0.19 0.16], [0.92 0.92 0.68 0.68]);
    plantLeaves = disk_mask(X, Y, 0.17, 0.64, 0.07) | disk_mask(X, Y, 0.13, 0.70, 0.05) | disk_mask(X, Y, 0.21, 0.71, 0.05);
    image = tint_region(image, plantStem, [0.53 0.34 0.18]);
    image = tint_region(image, plantLeaves, [0.18 0.52 0.22]);
    depth(plantStem | plantLeaves) = 0.28;
end

function image = render_haze(clearImage, depthMap, atmosphere, beta)
    clearImage = im2double(clearImage);
    atmosphere = reshape(atmosphere, 1, 1, 3);
    transmission = exp(-beta * depthMap);
    transmission = min(max(transmission, 0.08), 1);
    image = clearImage .* repmat(transmission, [1 1 3]) + atmosphere .* repmat(1 - transmission, [1 1 3]);
    image = min(max(image, 0), 1);
end

function image = tint_region(image, mask, color)
    color = reshape(color, 1, 1, 3);
    for c = 1:3
        channel = image(:, :, c);
        channel(mask) = color(c);
        image(:, :, c) = channel;
    end
end

function image = add_glow(image, glowMask, color, strength)
    color = reshape(color, 1, 1, 3);
    glowMask = min(max(glowMask, 0), 1) * strength;
    for c = 1:3
        channel = image(:, :, c);
        channel = min(max(channel + glowMask * color(c), 0), 1);
        image(:, :, c) = channel;
    end
end

function mask = disk_mask(X, Y, cx, cy, r)
    mask = ((X - cx) .^ 2 + (Y - cy) .^ 2) <= r ^ 2;
end

function mask = make_tree_line(X, Y, startX, spacing, baselineY, radius, count)
    mask = false(size(X));
    for i = 0:count - 1
        x = startX + spacing * i;
        trunk = inpolygon(X, Y, [x - 0.006 x + 0.006 x + 0.009 x - 0.009], [1.00 1.00 baselineY baselineY]);
        crown = disk_mask(X, Y, x, baselineY - 0.10, radius) | disk_mask(X, Y, x - 0.02, baselineY - 0.04, radius * 0.75) | disk_mask(X, Y, x + 0.02, baselineY - 0.05, radius * 0.75);
        mask = mask | trunk | crown;
    end
end

function [windowsMask, windowsDepth] = building_windows(X, Y, left, right, top)
    windowsMask = false(size(X));
    windowsDepth = NaN(size(X));
    width = right - left;
    height = 1 - top;
    cols = max(2, floor(width / 0.03));
    rows = max(2, floor(height / 0.06));
    winWidth = width / (cols + 1) * 0.45;
    winHeight = height / (rows + 1) * 0.18;

    for r = 1:rows
        for c = 1:cols
            cx = left + c * width / (cols + 1);
            cy = top + r * height / (rows + 1);
            mask = inpolygon(X, Y, ...
                [cx - winWidth cx + winWidth cx + winWidth cx - winWidth], ...
                [cy - winHeight cy - winHeight cy + winHeight cy + winHeight]);
            windowsMask = windowsMask | mask;
            windowsDepth(mask) = 0.50;
        end
    end
end
