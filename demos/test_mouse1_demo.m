%% Test DANNCE demo data with Label3D.m's plotCameras method
%  and actual first video frames from the DANNCE demo dataset.

clear; close all; clc;

% Add Label3D directory to path (assuming script is in Label3D/)
% If Label3D.m is in a different relative location, adjust this path.
% addpath(pwd); % Or specify the full path to Label3D.m's directory

% --- Configuration ---
% Path to the DANNCE demo .mat file
demoMatFile = fullfile('dannce', 'demo', 'markerless_mouse_1', 'label3d_demo.mat');

% Base path for DANNCE demo videos (assuming label3d_demo.mat is in markerless_mouse_1/)
[demoBaseDir, ~, ~] = fileparts(demoMatFile);
% CORRECTED: Add 'demo-vids' to the path
demoVideoBaseDir = fullfile(demoBaseDir, 'demo-vids'); 

nFramesToLoad = 1; % Number of frames to load from the start of each video

% --- Load DANNCE Demo Calibration Data ---
fprintf('Loading DANNCE demo calibration data from: %s\n', demoMatFile);
if ~exist(demoMatFile, 'file')
    error('DANNCE demo .mat file not found: %s.', demoMatFile);
end
demoData = load(demoMatFile);

if ~isfield(demoData, 'params')
    error('Demo .mat missing ''params'' field.');
end
dannceCamParams = demoData.params;
fprintf('Loaded %d camera parameter sets from DANNCE demo file.\n', numel(dannceCamParams));

if ~isfield(demoData, 'camnames')
    error('Demo .mat missing ''camnames'' field. Cannot locate videos.');
end
camNames = demoData.camnames;
numCameras = numel(dannceCamParams);

if numel(camNames) ~= numCameras
    error('Mismatch between number of cameras in params (%d) and camnames (%d).', numCameras, numel(camNames));
end

% --- Load Actual Video Frames --- 
fprintf('Loading %d frame(s) for each of %d cameras...\n', nFramesToLoad, numCameras);
actualVideos = cell(numCameras, 1);

for i = 1:numCameras
    currentCamName = camNames{i}; % camNames is a cell array of strings
    % Video files are often named 0.mp4, 1.mp4 etc. in subfolders named Camera1, Camera2 etc.
    % Or sometimes the prefix is directly in the filename in a single folder.
    % Assuming DANNCE structure: demoVideoBaseDir/CameraX/0.mp4
    % This was corrected based on user feedback where 'demo-vids' is part of the path.
    videoFilePath = fullfile(demoVideoBaseDir, currentCamName, '0.mp4');
    
    fprintf('  Attempting to load from: %s\n', videoFilePath);
    if ~exist(videoFilePath, 'file')
        % Fallback: try looking for video files like CameraX.mp4 directly in demoVideoBaseDir
        % This is less common for DANNCE but a possible alternative structure.
        videoFilePathFallback = fullfile(demoVideoBaseDir, [currentCamName '.mp4']);
        fprintf('    Primary path not found. Trying fallback: %s\n', videoFilePathFallback);
        if exist(videoFilePathFallback, 'file')
            videoFilePath = videoFilePathFallback;
        else
            warning('Video file not found for %s at expected paths. Skipping this camera.', currentCamName);
            % Create minimal empty video data so Label3D constructor doesn't fail on cell size
            actualVideos{i} = zeros(1,1,1,0,'uint8'); % Minimal empty data
            continue;
        end
    end
    
    try
        vr = VideoReader(videoFilePath);
        if vr.NumFrames < nFramesToLoad
            warning('Video %s has only %d frames, less than requested %d. Loading all available frames.', videoFilePath, vr.NumFrames, nFramesToLoad);
            framesToRead = vr.NumFrames;
        else
            framesToRead = nFramesToLoad;
        end
        
        if framesToRead == 0
            fprintf('    Video %s has 0 frames or 0 frames to read. Using empty data.\n', videoFilePath);
            actualVideos{i} = zeros(vr.Height, vr.Width, 3, 0, 'uint8');
        else
            % Preallocate for speed if loading multiple frames
            videoData = zeros(vr.Height, vr.Width, vr.BitsPerPixel/8, framesToRead, 'uint8');
            for frameNum = 1:framesToRead
                videoData(:,:,:,frameNum) = read(vr, frameNum);
            end
            actualVideos{i} = videoData;
            fprintf('    Loaded %d frame(s) from %s (Size: %dx%dx%dx%d).\n', ...
                framesToRead, videoFilePath, size(videoData,1),size(videoData,2),size(videoData,3),size(videoData,4));
        end
    catch ME_vid
        warning('Error loading video for %s: %s. Skipping this camera.', currentCamName, ME_vid.message);
        actualVideos{i} = zeros(1,1,1,0,'uint8'); % Minimal empty data on error
    end
end

% --- Dummy Skeleton (remains the same) ---
dummySkeleton.joint_names = {'joint1'};
dummySkeleton.joints_idx = [1 1]; 
dummySkeleton.color = [1 0 0];    

% --- Instantiate Label3D Object ---
fprintf('Instantiating Label3D object with actual video frames...\n');
try
    label3d_obj = Label3D(dannceCamParams, actualVideos, dummySkeleton, 'Visible', 'off', 'cameraNames', camNames);
    fprintf('Label3D object instantiated.\n');
catch ME
    fprintf('Error instantiating Label3D: %s\n', ME.message);
    fprintf('Make sure Label3D.m and its dependencies are on the MATLAB path.\n');
    rethrow(ME);
end

% --- Use Label3D's own plotCameras method (remains the same) ---
if exist('label3d_obj', 'var') && isvalid(label3d_obj)
    fprintf('Calling label3d_obj.plotCameras()...\n');
    try
        label3d_obj.plotCameras(); 
        title(gca, 'Camera Poses via Label3D.plotCameras() from DANNCE Demo Data & Video Frames');
        disp('plotCameras() called. Check the figure window.');
    catch ME_plot
        fprintf('Error calling label3d_obj.plotCameras(): %s\n', ME_plot.message);
        rethrow(ME_plot);
    end
else
    fprintf('Label3D object was not created successfully. Skipping plotCameras().\n');
end 