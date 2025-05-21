%% Resume a labeling session given a saved label3D session and a frame cache file

clear all;
close all;
addpath(genpath('deps'));
addpath(genpath('skeletons'));

%% Configuration variables -- SET THESE BEFORE RUNNING

% Path to the DANNCE project folder
% This folder should contain at least the following folders: "videos", "calibration"
projectFolder = "A:\EnclosureProjects\inprep\freemat\code\calibration\WMcalibration\Label3D";
labelDataFilename = '20250521_123240_Label3D.mat';
frameCacheFilename = 'frameCache_viz_n20_fStart1_fEnd4839_cams3_0.mat';

labelingFolder = fullfile(projectFolder, "labeling_output");

% --- NEW: Configuration for resuming a session ---
% These flags must match the settings used when the session was ORIGINALLY created (e.g., in freemat_run_label3d.m)
original_undistorted_images_flag = true;  % EXAMPLE: Set to true if original session used undistorted images
original_flip_views_vertically_flag = true; % EXAMPLE: Set to true if original session used flipped views

% --- END NEW CONFIG ---

% if this is true, automatically export the data after launching the gui
exportData = true;

% total number of frames in the video files. Important for exporting.
% this is not the number of frames to label. Usually a large # like 90000
% or 180000.
vidSourceTotalFrames = 90000;

%% Load frames from cache

% load label data to check for framesToLabel

labelDataFilePath = fullfile(labelingFolder, labelDataFilename);
frameCacheFilePath = fullfile(labelingFolder, frameCacheFilename);

labelDataFileInfo = who ('-file', labelDataFilePath);

% Load the correct variable name from the frame cache file
tmp = load(frameCacheFilePath, "cachedFramesToLabelIndices");

% Check if 'cachedFramesToLabelIndices' was actually loaded
if ~isfield(tmp, 'cachedFramesToLabelIndices')
    error('ResumeError: cachedFramesToLabelIndices not found in frame cache file: %s. Please ensure the cache file is correct and contains this variable.', frameCacheFilePath);
end
frameCacheFramesToLabel = tmp.cachedFramesToLabelIndices;

framesToLabel = 0;
loaded_nAnimals = 0;
loaded_cameraNames = {};

if ismember('framesToLabel', labelDataFileInfo)
    % Load framesToLabel, nAnimalsInSession, and cameraNamesToSave from the Label3D .mat file
    tmp_label_data = load(labelDataFilePath, "framesToLabel", "nAnimalsInSession", "cameraNamesToSave");
    labelDataFramesToLabel = tmp_label_data.framesToLabel;

    if isfield(tmp_label_data, 'nAnimalsInSession')
        loaded_nAnimals = tmp_label_data.nAnimalsInSession;
    else
        error('ResumeError: nAnimalsInSession not found in %s. Cannot resume.', labelDataFilePath);
    end

    if isfield(tmp_label_data, 'cameraNamesToSave')
        loaded_cameraNames = tmp_label_data.cameraNamesToSave;
        if ~iscell(loaded_cameraNames) % Ensure it's a cell array
            loaded_cameraNames = cellstr(loaded_cameraNames);
        end
    else
        error('ResumeError: cameraNamesToSave not found in %s. Cannot resume.', labelDataFilePath);
    end

    if isequaln(labelDataFramesToLabel, frameCacheFramesToLabel)
        disp("Frame cache 'framesToLabel' matches 'framesToLabel' in Label3D .mat file. Loading cached video data...");
        framesToLabel = labelDataFramesToLabel;
    else
        disp("Frame cache frameToLabel not equal to labelData frameToLabel." + ...
            " Try a different " + ...
            "frame cache file, or generate a new frame cache using example.m")
        fprintf("Did you forget to update 'frameCacheFilename'? E.g. 100 vs 75 frames.\n")
        fprintf("\nExiting script\n");
        return;
    end
else
    disp("Label data is missing frames to label. Attempting to generate" + ...
        " framesToLabel using uniform sampling")

    nFramesWholeVideo = input("Enter the # of frames in the entire video" + ...
        " (integer) and press return: ");
    fprintf("\n")
    nFramesToLabel = input("Enter the original # of frames to label" + ...
        " (integer) and press return: ");
    fprintf("\n")
    maybeFramesToLabel = round(linspace(1, nFramesWholeVideo, nFramesToLabel));
    
    if isequaln(maybeFramesToLabel, frameCacheFramesToLabel)
        disp("Evenly spaced frames appears to match cache frame numbers." + ...
            " Loading cached data ..." + ...
            " may take a few seconds")
        framesToLabel = maybeFramesToLabel;
    else
        disp("Evenly spaced frames is not accurate. Try creating a " + ...
            "framesToLabel array in the labelData file with the same list " + ...
            "of frames as the original labeling session" + ...
            "\nExiting script")
        return;
    end
end


%% Load cached video frames

frameCacheData = load(frameCacheFilePath, "videos");
videos = frameCacheData.videos;


%% Start Label3D

close all;
fprintf("Launching Label3D. May take a few seconds...\n")
labelGui = Label3D(labelDataFilePath, videos, 'savePath', labelingFolder, ...
    'framesToLabel', framesToLabel, ...
    'nAnimals', loaded_nAnimals, ...
    'cameraNames', loaded_cameraNames, ...
    'undistortedImages', original_undistorted_images_flag, ...
    'flipViewsVertically', original_flip_views_vertically_flag);

%% Optionally export the data to the dannce data format and close the GUI

if exportData
    if numel(labelGui.skeleton.joint_names) > 3
        % DANNCE label3d export 
        exportFilename=sprintf("%sDANNCE_Label3D_dannce.mat", ...
            labelGui.sessionDatestr);
    else
        % COM label3d export
        exportFilename=sprintf("%sCOM_Label3D_dannce.mat", ...
            labelGui.sessionDatestr);
    end
    exportFolder=fullfile(projectFolder, "export");
    mkdir(exportFolder)
    fprintf("Exporting to folder %s\n", exportFolder);
    labelGui.exportDannce('basePath' , projectFolder, ...
        'totalFrames', vidSourceTotalFrames, ...
        'makeSync', true, ...
        'saveFolder' , exportFolder, ...
        'saveFilename', exportFilename)
    close all;
end
