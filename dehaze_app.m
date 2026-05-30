function dehaze_app
%DEHAZE_APP MATLAB中文单图去雾界面。

    appDir = fileparts(mfilename('fullpath'));
    demoInfo = create_demo_dataset(appDir);
    fontName = 'Microsoft YaHei';

    fig = figure( ...
        'Name', 'MATLAB图像去雾系统', ...
        'NumberTitle', 'off', ...
        'MenuBar', 'none', ...
        'ToolBar', 'none', ...
        'Color', [0.95 0.96 0.98], ...
        'Units', 'pixels', ...
        'Position', [120 80 1400 880], ...
        'Resize', 'on', ...
        'Visible', 'off');

    screen = get(0, 'ScreenSize');
    maxW = max(1100, screen(3) - 80);
    maxH = max(780, screen(4) - 120);
    targetW = min(1400, maxW);
    targetH = min(880, maxH);
    targetX = max(20, floor((screen(3) - targetW) / 2));
    targetY = max(20, floor((screen(4) - targetH) / 2));
    set(fig, 'Position', [targetX targetY targetW targetH]);
    movegui(fig, 'onscreen');
    set(fig, 'Visible', 'on');

    set(fig, ...
        'DefaultAxesFontName', fontName, ...
        'DefaultTextFontName', fontName, ...
        'DefaultUicontrolFontName', fontName, ...
        'DefaultAxesFontSize', 10, ...
        'DefaultTextFontSize', 10, ...
        'DefaultUicontrolFontSize', 10);

    handles = build_ui(fig, fontName, demoInfo);

    state = struct();
    state.original = [];
    state.result = [];
    state.info = struct();
    state.currentFilePath = '';
    state.demoInfo = demoInfo;

    guidata(fig, struct('handles', handles, 'state', state));

    refresh_views(fig);
    set_status(fig, '准备就绪，请先打开一张图像。');
end

function handles = build_ui(fig, fontName, demoInfo)
    headerColor = [0.12 0.36 0.60];
    bodyColor = [0.95 0.96 0.98];
    panelColor = [1 1 1];
    accentColor = [0.20 0.47 0.84];
    softColor = [0.28 0.58 0.36];
    neutralColor = [0.42 0.42 0.45];

    set(fig, 'Color', bodyColor);

    handles.header = uipanel('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.01 0.91 0.98 0.075], 'BorderType', 'none', ...
        'BackgroundColor', headerColor);

    handles.txtTitle = uicontrol('Parent', handles.header, 'Style', 'text', ...
        'Units', 'normalized', 'Position', [0.02 0.14 0.55 0.72], ...
        'String', 'MATLAB图像去雾系统', ...
        'BackgroundColor', headerColor, 'ForegroundColor', [1 1 1], ...
        'HorizontalAlignment', 'left', 'FontName', fontName, ...
        'FontSize', 17, 'FontWeight', 'bold');

    handles.leftPanel = uipanel('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.01 0.06 0.25 0.84], 'BackgroundColor', panelColor, ...
        'BorderType', 'etchedin');

    handles.rightPanel = uipanel('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.27 0.06 0.72 0.84], 'BackgroundColor', panelColor, ...
        'BorderType', 'etchedin');

    handles.txtStatus = uicontrol('Parent', fig, 'Style', 'text', ...
        'Units', 'normalized', 'Position', [0.01 0.01 0.98 0.04], ...
        'BackgroundColor', bodyColor, 'ForegroundColor', [0.25 0.25 0.25], ...
        'HorizontalAlignment', 'left', 'FontName', fontName, 'FontSize', 9.3, ...
        'String', '准备就绪。');

    create_section_label(handles.leftPanel, '操作', 0.93, fontName, headerColor);
    handles.btnLoad = create_button(handles.leftPanel, '打开图像', [0.06 0.82 0.40 0.08], @onLoadImage, fontName, accentColor, [1 1 1]);
    handles.btnRun = create_button(handles.leftPanel, '运行去雾', [0.54 0.82 0.40 0.08], @onRunCurrent, fontName, accentColor, [1 1 1]);
    handles.btnSave = create_button(handles.leftPanel, '保存结果', [0.06 0.73 0.40 0.08], @onSaveResult, fontName, softColor, [1 1 1]);
    handles.btnDemo = create_button(handles.leftPanel, '示例图', [0.54 0.73 0.40 0.08], @onLoadDemoImage, fontName, softColor, [1 1 1]);
    handles.btnReset = create_button(handles.leftPanel, '重置', [0.06 0.64 0.88 0.08], @onResetAll, fontName, neutralColor, [1 1 1]);

    create_section_label(handles.leftPanel, '参数', 0.56, fontName, headerColor);
    [handles.lblPatch, handles.edPatch] = create_param_row(handles.leftPanel, '暗通道窗口', '15', 0.48, fontName);
    [handles.lblOmega, handles.edOmega] = create_param_row(handles.leftPanel, '去雾系数', '0.95', 0.40, fontName);
    [handles.lblT0, handles.edT0] = create_param_row(handles.leftPanel, '最小透射率', '0.10', 0.32, fontName);
    [handles.lblRadius, handles.edRadius] = create_param_row(handles.leftPanel, '引导半径', '40', 0.24, fontName);
    [handles.lblEps, handles.edEps] = create_param_row(handles.leftPanel, '引导平滑', '0.001', 0.16, fontName);
    handles.chkEnhance = uicontrol('Parent', handles.leftPanel, 'Style', 'checkbox', ...
        'Units', 'normalized', 'Position', [0.06 0.08 0.88 0.05], ...
        'String', '自动增强', 'Value', 0, 'FontName', fontName, ...
        'BackgroundColor', panelColor, 'HorizontalAlignment', 'left');

    handles.txtOriginalTitle = create_tile_label(handles.rightPanel, '原图', [0.04 0.91 0.42 0.04], fontName, headerColor);
    handles.txtResultTitle = create_tile_label(handles.rightPanel, '去雾结果', [0.53 0.91 0.42 0.04], fontName, headerColor);
    handles.txtDarkTitle = create_tile_label(handles.rightPanel, '暗通道', [0.04 0.44 0.42 0.04], fontName, headerColor);
    handles.txtTransmissionTitle = create_tile_label(handles.rightPanel, '透射率', [0.53 0.44 0.42 0.04], fontName, headerColor);

    handles.axOriginal = create_image_axis(handles.rightPanel, [0.04 0.53 0.42 0.34]);
    handles.axResult = create_image_axis(handles.rightPanel, [0.53 0.53 0.42 0.34]);
    handles.axDark = create_image_axis(handles.rightPanel, [0.04 0.08 0.42 0.34]);
    handles.axTransmission = create_image_axis(handles.rightPanel, [0.53 0.08 0.42 0.34]);

    handles.btnDemo.TooltipString = ['示例图目录：' demoInfo.hazyDir];
end

function h = create_button(parent, label, position, callback, fontName, bgColor, fgColor)
    h = uicontrol('Parent', parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', position, 'String', label, 'Callback', callback, ...
        'FontName', fontName, 'FontWeight', 'bold', 'FontSize', 10, ...
        'BackgroundColor', bgColor, 'ForegroundColor', fgColor);
end

function [lbl, edit] = create_param_row(parent, label, value, y, fontName)
    lbl = uicontrol('Parent', parent, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.06 y 0.46 0.05], 'String', label, ...
        'BackgroundColor', get(parent, 'BackgroundColor'), 'ForegroundColor', [0.2 0.2 0.2], ...
        'HorizontalAlignment', 'left', 'FontName', fontName, 'FontSize', 9.2);
    edit = uicontrol('Parent', parent, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.56 y - 0.005 0.31 0.055], 'String', value, ...
        'BackgroundColor', [1 1 1], 'FontName', fontName, 'FontSize', 9.2);
end

function create_section_label(parent, label, y, fontName, color)
    uicontrol('Parent', parent, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.06 y 0.88 0.035], 'String', label, ...
        'BackgroundColor', get(parent, 'BackgroundColor'), 'ForegroundColor', color, ...
        'HorizontalAlignment', 'left', 'FontName', fontName, ...
        'FontSize', 10.5, 'FontWeight', 'bold');
end

function h = create_tile_label(parent, label, position, fontName, color)
    h = uicontrol('Parent', parent, 'Style', 'text', 'Units', 'normalized', ...
        'Position', position, 'String', label, ...
        'BackgroundColor', get(parent, 'BackgroundColor'), 'ForegroundColor', color, ...
        'HorizontalAlignment', 'left', 'FontName', fontName, ...
        'FontSize', 10.2, 'FontWeight', 'bold');
end

function ax = create_image_axis(parent, position)
    ax = axes('Parent', parent, 'Units', 'normalized', 'Position', position, ...
        'Box', 'on', 'XTick', [], 'YTick', [], 'Color', [0.98 0.99 1]);
    axis(ax, 'off');
end

function onLoadImage(src, ~)
    fig = ancestor(src, 'figure');
    [file, path] = uigetfile({'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff', '图像文件'; '*.*', '所有文件'}, '选择一张雾图');
    if isequal(file, 0)
        return;
    end
    load_image_into_state(fig, fullfile(path, file));
    set_status(fig, ['已加载：' file]);
end

function onLoadDemoImage(src, ~)
    fig = ancestor(src, 'figure');
    S = guidata(fig);
    imagePath = first_image_in_folder(S.state.demoInfo.hazyDir);
    if isempty(imagePath)
        errordlg('没有找到示例图。', '示例图缺失');
        return;
    end
    load_image_into_state(fig, imagePath);
    [~, name, ext] = fileparts(imagePath);
    set_status(fig, ['已载入示例图：' name ext]);
end

function onRunCurrent(src, ~)
    fig = ancestor(src, 'figure');
    S = guidata(fig);
    if isempty(S.state.original)
        errordlg('请先打开图像。', '没有输入图像');
        return;
    end

    opts = read_options(S.handles);
    set_status(fig, '正在去雾，请稍候...');
    drawnow;

    tic;
    [resultImage, info] = dehaze_image(S.state.original, opts);
    elapsed = toc;

    S.state.result = resultImage;
    S.state.info = info;
    guidata(fig, S);

    refresh_views(fig);

    if isempty(S.state.currentFilePath)
        sourceName = '当前图像';
    else
        [~, sourceName, ext] = fileparts(S.state.currentFilePath);
        sourceName = [sourceName ext];
    end
    set_status(fig, sprintf('去雾完成：%s，耗时 %.2f 秒。', sourceName, elapsed));
end

function onSaveResult(src, ~)
    fig = ancestor(src, 'figure');
    S = guidata(fig);
    if isempty(S.state.result)
        errordlg('请先运行去雾，再保存结果。', '没有可保存的结果');
        return;
    end

    if isempty(S.state.currentFilePath)
        defaultName = '去雾结果.png';
    else
        [~, baseName] = fileparts(S.state.currentFilePath);
        defaultName = [baseName '_dehaze.png'];
    end

    [file, path] = uiputfile({'*.png'; '*.jpg'; '*.bmp'; '*.tif'}, '保存去雾结果', defaultName);
    if isequal(file, 0)
        return;
    end

    imwrite(S.state.result, fullfile(path, file));
    set_status(fig, ['结果已保存：' file]);
end

function onResetAll(src, ~)
    fig = ancestor(src, 'figure');
    S = guidata(fig);
    S.state.original = [];
    S.state.result = [];
    S.state.info = struct();
    S.state.currentFilePath = '';
    guidata(fig, S);

    refresh_views(fig);
    set_status(fig, '已重置。');
end

function load_image_into_state(fig, filePath)
    S = guidata(fig);
    imageData = imread(filePath);
    if ndims(imageData) == 3 && size(imageData, 3) > 3
        imageData = imageData(:, :, 1:3);
    end
    S.state.original = imageData;
    S.state.result = [];
    S.state.info = struct();
    S.state.currentFilePath = filePath;
    guidata(fig, S);
    refresh_views(fig);
end

function opts = read_options(handles)
    opts.patchSize = max(1, round(read_number(handles.edPatch, 15)));
    opts.omega = clamp(read_number(handles.edOmega, 0.95), 0, 1);
    opts.t0 = clamp(read_number(handles.edT0, 0.10), 0.01, 0.5);
    opts.guidedRadius = max(1, round(read_number(handles.edRadius, 40)));
    opts.guidedEps = max(read_number(handles.edEps, 0.001), 1e-6);
    opts.topPercent = 0.001;
    opts.enhanceContrast = logical(get(handles.chkEnhance, 'Value'));
end

function value = read_number(handle, defaultValue)
    value = str2double(get(handle, 'String'));
    if isnan(value) || ~isfinite(value)
        value = defaultValue;
    end
end

function value = clamp(value, minValue, maxValue)
    value = min(max(value, minValue), maxValue);
end

function refresh_views(fig)
    S = guidata(fig);

    if isempty(S.state.original)
        show_placeholder(S.handles.axOriginal, '未加载');
    else
        show_rgb_image(S.handles.axOriginal, S.state.original);
    end

    if isempty(S.state.result)
        show_placeholder(S.handles.axResult, '等待运行');
    else
        show_rgb_image(S.handles.axResult, S.state.result);
    end

    if isfield(S.state.info, 'darkChannel') && ~isempty(S.state.info.darkChannel)
        show_gray_image(S.handles.axDark, S.state.info.darkChannel);
    else
        show_placeholder(S.handles.axDark, '未生成');
    end

    if isfield(S.state.info, 'transmissionRefined') && ~isempty(S.state.info.transmissionRefined)
        show_gray_image(S.handles.axTransmission, S.state.info.transmissionRefined);
    else
        show_placeholder(S.handles.axTransmission, '未生成');
    end
end

function show_rgb_image(ax, imageData)
    cla(ax);
    imshow(to_display_rgb(imageData), 'Parent', ax);
    axis(ax, 'image');
    axis(ax, 'off');
end

function show_gray_image(ax, mapData)
    cla(ax);
    gray = im2double(mapData);
    gray = min(max(gray, 0), 1);
    imshow(repmat(gray, [1 1 3]), 'Parent', ax);
    axis(ax, 'image');
    axis(ax, 'off');
end

function show_placeholder(ax, message)
    cla(ax);
    set(ax, 'Color', [0.98 0.99 1]);
    axis(ax, [0 1 0 1]);
    axis(ax, 'off');
    text('Parent', ax, 'Units', 'normalized', 'Position', [0.5 0.5 0], ...
        'String', message, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'Color', [0.50 0.50 0.54], ...
        'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'none');
end

function imageRGB = to_display_rgb(imageData)
    imageRGB = im2double(imageData);
    if ndims(imageRGB) == 3 && size(imageRGB, 3) > 3
        imageRGB = imageRGB(:, :, 1:3);
    elseif ismatrix(imageRGB)
        imageRGB = repmat(imageRGB, [1 1 3]);
    end
    imageRGB = min(max(imageRGB, 0), 1);
end

function set_status(fig, message)
    S = guidata(fig);
    set(S.handles.txtStatus, 'String', message);
    drawnow;
end

function imagePath = first_image_in_folder(folderPath)
    imagePath = '';
    if isempty(folderPath) || ~ischar(folderPath) || ~exist(folderPath, 'dir')
        return;
    end
    exts = {'*.png', '*.jpg', '*.jpeg', '*.bmp', '*.tif', '*.tiff'};
    for i = 1:numel(exts)
        files = dir(fullfile(folderPath, exts{i}));
        if ~isempty(files)
            [~, order] = sort(lower({files.name}));
            files = files(order);
            imagePath = fullfile(folderPath, files(1).name);
            return;
        end
    end
end



