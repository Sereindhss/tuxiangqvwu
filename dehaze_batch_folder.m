function batch = dehaze_batch_folder(selectedRoot, opts, outputRoot, progressFcn)
%DEHAZE_BATCH_FOLDER Batch dehaze images under a dataset root.

    if nargin < 2 || isempty(opts)
        opts = struct();
    end
    if nargin < 3
        outputRoot = '';
    end
    if nargin < 4
        progressFcn = [];
    end

    if ~exist(selectedRoot, 'dir')
        error('Selected folder does not exist: %s', selectedRoot);
    end

    layout = resolve_dataset_layout(selectedRoot, outputRoot);
    files = collect_image_files(layout.sourceRoot);

    batch = struct();
    batch.selectedRoot = selectedRoot;
    batch.sourceRoot = layout.sourceRoot;
    batch.referenceRoot = layout.referenceRoot;
    batch.outputRoot = layout.outputRoot;
    batch.records = repmat(empty_record(), 1, numel(files));
    batch.tableData = cell(0, 6);
    batch.summary = struct();

    if isempty(files)
        batch.summary = summarize_records(batch.records, batch.sourceRoot, batch.referenceRoot, batch.outputRoot);
        return;
    end

    referenceIndex = build_reference_index(layout.referenceRoot);

    for k = 1:numel(files)
        batch.records(k) = process_one_file(files(k), opts, layout.outputRoot, referenceIndex);
        if ~isempty(progressFcn)
            try
                progressFcn(k, numel(files), batch.records(k));
            catch
            end
        end
        drawnow;
    end

    batch.tableData = records_to_table_data(batch.records, batch.sourceRoot, batch.outputRoot);
    batch.summary = summarize_records(batch.records, batch.sourceRoot, batch.referenceRoot, batch.outputRoot);
end

function layout = resolve_dataset_layout(selectedRoot, outputRoot)
    layout.selectedRoot = selectedRoot;
    layout.sourceRoot = detect_source_root(selectedRoot);
    layout.referenceRoot = detect_reference_root(selectedRoot, layout.sourceRoot);

    if isempty(outputRoot)
        layout.outputRoot = detect_output_root(selectedRoot, layout.sourceRoot);
    else
        layout.outputRoot = outputRoot;
    end
end

function sourceRoot = detect_source_root(selectedRoot)
    sourceCandidates = {'hazy', 'input', 'images', 'source'};
    for i = 1:numel(sourceCandidates)
        candidate = fullfile(selectedRoot, sourceCandidates{i});
        if has_image_files(candidate)
            sourceRoot = candidate;
            return;
        end
    end
    sourceRoot = selectedRoot;
end

function referenceRoot = detect_reference_root(selectedRoot, sourceRoot)
    referenceRoot = '';
    refCandidates = {'gt', 'GT', 'clear', 'reference', 'ref', 'clean', 'truth'};

    rootsToCheck = {selectedRoot};
    parentRoot = fileparts(selectedRoot);
    if ~isempty(parentRoot) && ~strcmpi(parentRoot, selectedRoot)
        rootsToCheck{end + 1} = parentRoot; %#ok<AGROW>
    end

    for r = 1:numel(rootsToCheck)
        baseRoot = rootsToCheck{r};
        for c = 1:numel(refCandidates)
            candidate = fullfile(baseRoot, refCandidates{c});
            if has_image_files(candidate)
                referenceRoot = candidate;
                return;
            end
        end
    end

    if ~strcmpi(sourceRoot, selectedRoot)
        sourceParent = fileparts(sourceRoot);
        for c = 1:numel(refCandidates)
            candidate = fullfile(sourceParent, refCandidates{c});
            if has_image_files(candidate)
                referenceRoot = candidate;
                return;
            end
        end
    end
end

function outputRoot = detect_output_root(selectedRoot, sourceRoot)
    sourceName = folder_name(sourceRoot);
    selectedName = folder_name(selectedRoot);

    if strcmpi(sourceRoot, selectedRoot)
        if strcmpi(sourceName, 'hazy') || strcmpi(sourceName, 'input') || strcmpi(selectedName, 'hazy') || strcmpi(selectedName, 'input')
            parentRoot = fileparts(selectedRoot);
            if isempty(parentRoot)
                outputRoot = fullfile(selectedRoot, 'output');
            else
                outputRoot = fullfile(parentRoot, 'output');
            end
        else
            outputRoot = fullfile(selectedRoot, 'dehaze_output');
        end
    else
        outputRoot = fullfile(selectedRoot, 'output');
    end
end

function name = folder_name(pathStr)
    [~, name] = fileparts(pathStr);
    if isempty(name)
        name = pathStr;
    end
end

function record = empty_record()
    record = struct( ...
        'fileName', '', ...
        'relativePath', '', ...
        'inputPath', '', ...
        'referencePath', '', ...
        'outputPath', '', ...
        'status', '', ...
        'elapsed', NaN, ...
        'psnr', NaN, ...
        'ssim', NaN, ...
        'note', '');
end

function record = process_one_file(fileInfo, opts, outputRoot, referenceIndex)
    record = empty_record();
    record.fileName = fileInfo.name;
    record.relativePath = fileInfo.relativePath;
    record.inputPath = fileInfo.fullPath;

    try
        sourceImage = imread(fileInfo.fullPath);
        tic;
        [resultImage, ~] = dehaze_image(sourceImage, opts);
        record.elapsed = toc;

        record.outputPath = fullfile(outputRoot, fileInfo.relativePath);
        ensure_parent_folder(record.outputPath);
        imwrite(resultImage, record.outputPath);
        record.status = '成功';

        referencePath = find_reference_path(referenceIndex, fileInfo);
        if ~isempty(referencePath)
            record.referencePath = referencePath;
            [record.psnr, record.ssim, record.note] = compare_with_reference(resultImage, referencePath);
        else
            record.note = '无参考图';
        end
    catch ME
        record.status = '失败';
        record.note = ME.message;
        if record.elapsed ~= record.elapsed
            record.elapsed = NaN;
        end
    end
end

function [psnrValue, ssimValue, note] = compare_with_reference(resultImage, referencePath)
    note = '';
    referenceImage = imread(referencePath);
    [resultRGB, referenceRGB, resized] = align_metric_images(resultImage, referenceImage);
    if resized
        note = '参考图已缩放';
    end
    psnrValue = safe_psnr(resultRGB, referenceRGB);
    ssimValue = safe_ssim(resultRGB, referenceRGB);
end

function [resultRGB, referenceRGB, resized] = align_metric_images(resultImage, referenceImage)
    resultRGB = ensure_rgb_double(resultImage);
    referenceRGB = ensure_rgb_double(referenceImage);

    resized = false;
    if size(resultRGB, 1) ~= size(referenceRGB, 1) || size(resultRGB, 2) ~= size(referenceRGB, 2)
        resultRGB = imresize(resultRGB, [size(referenceRGB, 1) size(referenceRGB, 2)]);
        resized = true;
    end
end

function imageRGB = ensure_rgb_double(imageIn)
    imageRGB = im2double(imageIn);
    if ndims(imageRGB) == 2
        imageRGB = repmat(imageRGB, [1 1 3]);
    elseif size(imageRGB, 3) > 3
        imageRGB = imageRGB(:, :, 1:3);
    end
    imageRGB = min(max(imageRGB, 0), 1);
end

function value = safe_psnr(A, B)
    diff = A - B;
    mse = mean(diff(:) .^ 2);
    if mse <= 0
        value = Inf;
    else
        value = 10 * log10(1 / mse);
    end
end

function value = safe_ssim(A, B)
    if exist('ssim', 'file') == 2
        value = ssim(A, B);
        return;
    end

    if ndims(A) == 3
        A = rgb2gray(A);
    end
    if ndims(B) == 3
        B = rgb2gray(B);
    end

    A = im2double(A);
    B = im2double(B);

    muA = mean(A(:));
    muB = mean(B(:));
    varA = mean((A(:) - muA) .^ 2);
    varB = mean((B(:) - muB) .^ 2);
    covAB = mean((A(:) - muA) .* (B(:) - muB));

    c1 = (0.01)^2;
    c2 = (0.03)^2;
    value = ((2 * muA * muB + c1) * (2 * covAB + c2)) / ((muA^2 + muB^2 + c1) * (varA + varB + c2));
end

function tableData = records_to_table_data(records, sourceRoot, outputRoot)
    if isempty(records)
        tableData = cell(0, 6);
        return;
    end

    tableData = cell(numel(records), 6);
    for k = 1:numel(records)
        tableData{k, 1} = display_path(records(k).relativePath, records(k).fileName);
        tableData{k, 2} = display_status(records(k));
        tableData{k, 3} = format_number(records(k).elapsed, 2);
        tableData{k, 4} = format_number(records(k).psnr, 2);
        tableData{k, 5} = format_number(records(k).ssim, 4);
        tableData{k, 6} = display_output_path(records(k).outputPath, sourceRoot, outputRoot);
    end
end

function textValue = display_path(relativePath, fileName)
    if isempty(relativePath)
        textValue = fileName;
    else
        textValue = strrep(relativePath, '\', '/');
    end
end

function textValue = display_output_path(outputPath, sourceRoot, outputRoot)
    if isempty(outputPath)
        textValue = '-';
        return;
    end
    if nargin >= 3 && ~isempty(outputRoot) && strncmpi(outputPath, outputRoot, numel(outputRoot))
        textValue = outputPath(numel(outputRoot) + 2:end);
    elseif nargin >= 2 && ~isempty(sourceRoot) && strncmpi(outputPath, sourceRoot, numel(sourceRoot))
        textValue = outputPath(numel(sourceRoot) + 2:end);
    else
        textValue = outputPath;
    end
    textValue = strrep(textValue, '\', '/');
end

function textValue = display_status(record)
    if strcmp(record.status, '成功') && isempty(record.referencePath)
        textValue = '成功(无参考)';
    else
        textValue = record.status;
    end
    if isempty(textValue)
        textValue = '-';
    end
end

function textValue = format_number(value, digits)
    if isempty(value) || isnan(value)
        textValue = '-';
    elseif isinf(value)
        textValue = 'Inf';
    else
        textValue = sprintf(['%.' num2str(digits) 'f'], value);
    end
end

function summary = summarize_records(records, sourceRoot, referenceRoot, outputRoot)
    summary = struct();
    summary.totalCount = numel(records);
    summary.successCount = 0;
    summary.metricCount = 0;
    summary.meanElapsed = NaN;
    summary.meanPsnr = NaN;
    summary.meanSsim = NaN;
    summary.sourceRoot = sourceRoot;
    summary.referenceRoot = referenceRoot;
    summary.outputRoot = outputRoot;
    summary.displayText = '尚未运行批量测试。';
    summary.detailText = '';

    if isempty(records)
        return;
    end

    successFlags = strcmp({records.status}, '成功');
    summary.successCount = sum(successFlags);

    elapsedValues = [records.elapsed];
    elapsedValues = elapsedValues(isfinite(elapsedValues));
    if ~isempty(elapsedValues)
        summary.meanElapsed = mean(elapsedValues);
    end

    psnrValues = [records.psnr];
    psnrValues = psnrValues(isfinite(psnrValues));
    if ~isempty(psnrValues)
        summary.metricCount = numel(psnrValues);
        summary.meanPsnr = mean(psnrValues);
    end

    ssimValues = [records.ssim];
    ssimValues = ssimValues(isfinite(ssimValues));
    if ~isempty(ssimValues)
        summary.meanSsim = mean(ssimValues);
    end

    summary.displayText = build_summary_text(summary);
    summary.detailText = build_detail_text(summary);
end

function textValue = build_summary_text(summary)
    if summary.totalCount == 0
        textValue = '没有找到可处理的图像。';
        return;
    end

    if ~isempty(summary.referenceRoot)
        textValue = sprintf( ...
            '共 %d 张 | 成功 %d 张 | 带参考 %d 张 | 平均耗时 %s 秒 | 平均 PSNR %s dB | 平均 SSIM %s', ...
            summary.totalCount, summary.successCount, summary.metricCount, ...
            format_number(summary.meanElapsed, 2), format_number(summary.meanPsnr, 2), format_number(summary.meanSsim, 4));
    else
        textValue = sprintf( ...
            '共 %d 张 | 成功 %d 张 | 平均耗时 %s 秒 | 未找到参考图，未计算 PSNR/SSIM', ...
            summary.totalCount, summary.successCount, format_number(summary.meanElapsed, 2));
    end
end

function textValue = build_detail_text(summary)
    textValue = sprintf( ...
        '源目录: %s\n参考目录: %s\n输出目录: %s', ...
        display_or_dash(summary.sourceRoot), display_or_dash(summary.referenceRoot), display_or_dash(summary.outputRoot));
end

function textValue = display_or_dash(value)
    if isempty(value)
        textValue = '-';
    else
        textValue = strrep(value, '\', '/');
    end
end

function ensure_parent_folder(filePath)
    folder = fileparts(filePath);
    if ~isempty(folder) && ~exist(folder, 'dir')
        mkdir(folder);
    end
end

function index = build_reference_index(referenceRoot)
    index = struct();
    index.byRelative = containers.Map('KeyType', 'char', 'ValueType', 'char');
    index.byName = containers.Map('KeyType', 'char', 'ValueType', 'char');

    if isempty(referenceRoot) || ~exist(referenceRoot, 'dir')
        return;
    end

    files = collect_image_files(referenceRoot);
    for k = 1:numel(files)
        relKey = normalize_key(files(k).relativePath);
        nameKey = normalize_key(files(k).name);
        if ~isKey(index.byRelative, relKey)
            index.byRelative(relKey) = files(k).fullPath;
        end
        if ~isKey(index.byName, nameKey)
            index.byName(nameKey) = files(k).fullPath;
        end
    end
end

function referencePath = find_reference_path(referenceIndex, fileInfo)
    referencePath = '';
    if isempty(referenceIndex) || isempty(fileInfo)
        return;
    end

    relKey = normalize_key(fileInfo.relativePath);
    if isKey(referenceIndex.byRelative, relKey)
        referencePath = referenceIndex.byRelative(relKey);
        return;
    end

    nameKey = normalize_key(fileInfo.name);
    if isKey(referenceIndex.byName, nameKey)
        referencePath = referenceIndex.byName(nameKey);
    end
end

function key = normalize_key(value)
    key = lower(strrep(value, '\', '/'));
end

function tf = has_image_files(rootDir)
    tf = false;
    if isempty(rootDir) || ~exist(rootDir, 'dir')
        return;
    end

    imageExtensions = {'*.jpg', '*.jpeg', '*.png', '*.bmp', '*.tif', '*.tiff'};
    for i = 1:numel(imageExtensions)
        if ~isempty(dir(fullfile(rootDir, imageExtensions{i})))
            tf = true;
            return;
        end
    end
end

function files = collect_image_files(rootDir)
    files = struct('fullPath', {}, 'relativePath', {}, 'name', {}, 'baseName', {}, 'extension', {});
    if isempty(rootDir) || ~exist(rootDir, 'dir')
        return;
    end

    gather(rootDir);
    if isempty(files)
        return;
    end

    relativePaths = {files.relativePath};
    [~, order] = sort(lower(relativePaths));
    files = files(order);

    function gather(folder)
        items = dir(folder);
        for i = 1:numel(items)
            item = items(i);
            if item.isdir
                if should_skip_folder(item.name)
                    continue;
                end
                gather(fullfile(folder, item.name));
            else
                [~, baseName, extension] = fileparts(item.name);
                if ~is_image_extension(extension)
                    continue;
                end
                fullPath = fullfile(folder, item.name);
                entry = struct();
                entry.fullPath = fullPath;
                entry.relativePath = local_relative_path(fullPath, rootDir);
                entry.name = item.name;
                entry.baseName = baseName;
                entry.extension = extension;
                files(end + 1) = entry; %#ok<AGROW>
            end
        end
    end
end

function relativePath = local_relative_path(fullPath, rootDir)
    if strncmpi(fullPath, rootDir, numel(rootDir))
        startIndex = numel(rootDir) + 2;
        if startIndex <= numel(fullPath)
            relativePath = fullPath(startIndex:end);
            return;
        end
    end
    [~, name, ext] = fileparts(fullPath);
    relativePath = [name ext];
end

function tf = should_skip_folder(folderName)
    skipNames = {'.', '..', 'output', 'dehaze_output', 'result', 'results'};
    tf = any(strcmpi(folderName, skipNames));
end

function tf = is_image_extension(extension)
    imageExtensions = {'.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff'};
    tf = any(strcmpi(extension, imageExtensions));
end
