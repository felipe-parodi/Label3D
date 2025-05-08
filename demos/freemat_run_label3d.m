%% run_label3d.m
% Script to load data and launch the Label3D GUI for labeling two monkeys.

clear all;
close all;

% --- Add necessary paths ---
% Add paths to Label3D code and dependencies if not already on MATLAB path
addpath(genpath('deps')); % If Animator is in deps
addpath('.'); % Current folder for Label3D.m
fprintf('Setting up Label3D session...\n');

% =========================================================================
% --- Configuration ---
% =========================================================================

% --- Camera and Video Paths ---
% Define the camera names IN THE ORDER YOU WANT THEM LOADED/DISPLAYED
% This order must match the order of param files loaded
labelingCameraNames = {
    "Cam_001",
    "Cam_002",
    "Cam_003",
    "Cam_004",
    "Cam_007",
    % "Cam_008",
    % "Cam_009",
    % "Cam_010",
    % "Cam_011",
    % "Cam_012", 
    % "Cam_013",
    % "Cam_014",
    % "Cam_015",
    % "Cam_016",
    % "Cam_018",
    % "Cam_019",
    % "Cam_020",
    % "Cam_021",
    % "Cam_022",
    % "Cam_023",
    % "Cam_024",
    % "Cam_025",
    % "Cam_026",
    % "Cam_027",
    % "Cam_028"

    };
numCameras = numel(labelingCameraNames);

% --- Specify Paths for Automatic Video Discovery ---
% Directory containing the video files (e.g., calibration or experiment videos)
videoDir = "A:\EnclosureProjects\inprep\freemat\data\experiments\good\240528\video\calibration\fixed_timestamp";

% --- Derive other paths relative to videoDir ---
[baseVideoPath, ~, ~] = fileparts(videoDir);
[baseVideoPath, ~, ~] = fileparts(baseVideoPath); % Go up two levels
calibrationBaseDir = fullfile(baseVideoPath, 'calibration', 'fixed_timestamp', 'multical');

% Path to the extraction report containing camera name mappings
extractionReportPath = fullfile(calibrationBaseDir, 'extraction_report.txt');

% Directory containing *_params.mat files
paramDir = fullfile(calibrationBaseDir, 'label3d');

% --- Calibration and Skeleton Paths ---
% paramDir = "A:\EnclosureProjects\inprep\freemat\experiments\good\240528\video\calibration\fixed_timestamp\multical\label3d"; % Directory containing *_params.mat files - REMOVED
skeletonFile = fullfile('skeletons', 'coco17_skeleton.mat');

% --- Labeling Parameters ---
labelingDurationMinutes = 60; % Duration from the start of the video to sample from
framesPerMinute = 3;          % Number of frames to select per minute
frameRate = 40;               % Video frame rate in fps (used for calculation, checked against actual)
nAnimals = 2;                 % Number of animals to label

% --- Output/Cache Configuration ---
labelingOutputDir = fullfile(pwd, 'labeling_output'); % Folder to save Label3D sessions
enableVideoCache = true;     % Set to true to save loaded frames for faster restarts
useParallel = true;          % Set to true if Parallel Computing Toolbox is available

% =========================================================================
% --- Parse Extraction Report and Find Video Paths ---
% =========================================================================
fprintf('Parsing extraction report: %s\n', extractionReportPath);

if ~exist(extractionReportPath, 'file')
    error('Extraction report file not found: %s', extractionReportPath);
end

camNameToPrefixMap = containers.Map('KeyType', 'char', 'ValueType', 'char');

try
    fid = fopen(extractionReportPath, 'r');
    if fid == -1
        error('Could not open extraction report file: %s', extractionReportPath);
    end

    % Regex to find lines like: Camera: e3v8217-... (Cam_001)
    % It captures the first 7 chars (prefix) and the Cam_XXX name
    regexPattern = 'Camera:\s+(\w{7}).*\((Cam_\d{3})\)';

    tline = fgetl(fid);
    while ischar(tline)
        tokens = regexp(tline, regexPattern, 'tokens');
        if ~isempty(tokens)
            prefix = tokens{1}{1};
            camName = tokens{1}{2};
            camNameToPrefixMap(camName) = prefix;
        end
        tline = fgetl(fid);
    end
    fclose(fid);
catch ME
    if fid ~= -1, fclose(fid); end % Ensure file is closed on error
    rethrow(ME);
end

fprintf('Found mappings for %d cameras in the report.\n', length(keys(camNameToPrefixMap)));

fprintf('Searching for video files in directory: %s\n', videoDir);
if ~exist(videoDir, 'dir')
    error('Video directory not found: %s', videoDir);
end

% List video files (adjust extensions if needed)
potentialVideoFiles = dir(fullfile(videoDir, '*.mp4'));
if isempty(potentialVideoFiles)
     warning('No *.mp4 files found in %s. Trying other extensions...', videoDir);
     % Add checks for other extensions if necessary (e.g., *.avi)
     % potentialVideoFiles = [potentialVideoFiles; dir(fullfile(videoDir, '*.avi'))];
end
if isempty(potentialVideoFiles)
     error('No video files found in directory: %s', videoDir);
end

videoPaths = cell(numCameras, 1);
foundCount = 0;
missingCameras = {};

for i = 1:numCameras
    currentCamName = labelingCameraNames{i};
    fprintf('  Looking for video for: %s... ', currentCamName);

    if ~isKey(camNameToPrefixMap, currentCamName)
        fprintf('ERROR: Camera name not found in extraction report.\n');
        missingCameras{end+1} = currentCamName;
        continue; % Skip this camera
    end

    prefix = camNameToPrefixMap(currentCamName);
    foundMatch = false;
    matchedFile = '';

    for j = 1:length(potentialVideoFiles)
        fname = potentialVideoFiles(j).name;
        if startsWith(fname, prefix)
            if foundMatch
                % Found a second match - this is ambiguous
                fprintf('ERROR: Ambiguous match! Found multiple files starting with prefix "%s" (e.g., "%s" and "%s").\n', prefix, matchedFile, fname);
                matchedFile = ''; % Reset match
                break;
            else
                % Found the first match
                matchedFile = fname;
                foundMatch = true;
                % Continue searching to detect ambiguity
            end
        end
    end

    if foundMatch && ~isempty(matchedFile)
        videoPaths{i} = fullfile(videoDir, matchedFile);
        fprintf('Found: %s\n', matchedFile);
        foundCount = foundCount + 1;
    elseif ~foundMatch
        fprintf('ERROR: No video file found starting with prefix "%s".\n', prefix);
        missingCameras{end+1} = currentCamName;
    else % Ambiguous match case
         missingCameras{end+1} = [currentCamName, ' (Ambiguous)'];
    end
end

% Final Check
if foundCount ~= numCameras
    error('Could not find matching video files for all requested cameras. Missing/Ambiguous: %s', strjoin(unique(missingCameras), ', '));
else
    fprintf('Successfully found video paths for all %d requested cameras.\n', numCameras);
end
% =========================================================================
% --- END VIDEO PATH FINDING ---
% =========================================================================


% =========================================================================
% --- Calculate Frames to Label (Adjusted for Video Length) ---
% =========================================================================
fprintf('Determining video lengths and calculating frame indices to load...\n');

% --- Find Minimum Video Length ---
minTotalFrames = Inf;
actualFrameRates = zeros(numCameras, 1); % Store actual frame rates

for i = 1:numCameras
    try
        fprintf('  Checking video length: %s\n', videoPaths{i});
        vr = VideoReader(videoPaths{i});
        if vr.NumFrames == 0
            warning('VideoReader reported 0 frames for %s. Check video file.', videoPaths{i});
            % Let's error out if a video has 0 frames as it breaks calculation
            error('Video file %s seems to have 0 frames.', videoPaths{i});
        end
        minTotalFrames = min(minTotalFrames, vr.NumFrames);
        actualFrameRates(i) = vr.FrameRate;
        % Optional: check if frame rates match config
        if abs(vr.FrameRate - frameRate) > 1 % Allow small tolerance
             warning('Video %d (%s) frame rate (%.2f) differs significantly from configured rate (%.2f)', ...
                     i, videoPaths{i}, vr.FrameRate, frameRate);
        end
    catch ME
        error('Could not read video file %s to determine length. Error: %s', videoPaths{i}, ME.message);
    end
end

if isinf(minTotalFrames)
    % This should theoretically not happen if the loop runs and files are valid
    error('Could not determine minimum video length. Check video files and paths.');
end
fprintf('  Minimum video length found: %d frames.\n', minTotalFrames);

% --- Calculate Effective Duration and Frame Count ---
% Calculate the desired end frame based on configuration
endFrameFromConfig = round(labelingDurationMinutes * 60 * frameRate);

% Use the shorter of the configured duration or actual video length
actualEndFrame = min(endFrameFromConfig, minTotalFrames);

% Calculate the number of frames to label based on the *actual* duration used
% Use the average actual frame rate for calculation? Or stick to configured?
% Sticking to configured frameRate for now, as it defines the target sampling density.
effectiveDurationMinutes = actualEndFrame / frameRate / 60;
% Ensure at least 1 frame is requested if duration > 0 and actualEndFrame > 0
if actualEndFrame > 0
    nFramesToLabelAdjusted = max(1, floor(effectiveDurationMinutes * framesPerMinute));
else
    nFramesToLabelAdjusted = 0; % Cannot select frames if effective duration is zero
end

if actualEndFrame < 1
    warning('Minimum video length or configured duration results in 0 frames available for sampling.')
    framesToLabelIndices = [];
else
    % Calculate the 1-based indices of the frames to load, spaced evenly within actual range
    framesToLabelIndices = round(linspace(1, actualEndFrame, nFramesToLabelAdjusted));
    % Ensure indices are unique and sorted (linspace should handle this, but good practice)
    framesToLabelIndices = unique(sort(framesToLabelIndices));
end

% Update nFramesToLabel for subsequent use (e.g., caching, allocation)
nFramesToLabel = numel(framesToLabelIndices);

fprintf('Selected %d frames to label, using actual end frame %d (min of config and video length).\n', nFramesToLabel, actualEndFrame);


% =========================================================================
% --- Load Camera Parameters ---
% =========================================================================
fprintf('Loading camera parameters from %s...\n', paramDir);

myCamParams = cell(numCameras, 1);
for i = 1:numCameras
    camName = labelingCameraNames{i};
    paramFile = fullfile(paramDir, camName + "_params.mat");

    if ~exist(paramFile, 'file')
        error('Parameter file not found: %s. Did create_label3d_calib_mats.py run correctly?', paramFile);
    end
    fprintf('  Loading: %s\n', paramFile);
    loadedData = load(paramFile);
    % --- BEGIN LOGGING LOADED DATA ---
    fprintf('    Loaded %s - r matrix:\n', camName);
    disp(loadedData.r);
    fprintf('    Loaded %s - t vector:\n', camName);
    disp(loadedData.t);
    % --- END LOGGING LOADED DATA ---
    % Ensure the necessary field 'r' exists (as saved by the Python script)
    if ~isfield(loadedData, 'r')
       error('Field \'\'r\'\' not found in %s. Please re-run the Python script create_label3d_calib_mats.py after the latest update.', paramFile);
    end
    myCamParams{i} = loadedData;
end
fprintf('Loaded parameters for %d cameras.\n', numel(myCamParams));

% --- Apply Corrective Rotation (World X-axis 180 deg) ---
% fprintf('\nApplying corrective transformation to loaded parameters...\n');
% % R_fix = diag([1.0, -1.0, -1.0]); % 180-degree rotation around World X-axis
% R_fix = diag([-1.0, -1.0, 1.0]); % <--- CHANGE: 180-degree rotation around World Z-axis
% for i = 1:numCameras
%     original_r = myCamParams{i}.r;
%     original_t = myCamParams{i}.t; % This is loaded as 1x3 row vector
%     
%     % Apply rotation consistently to both r (R_c_w) and t (T_c_w)
%     corrected_r = R_fix * original_r;
%     corrected_t_col = R_fix * original_t'; % Correct: [3x3]*[3x1] -> [3x1]
%     corrected_t = corrected_t_col'; % Transpose back to 1x3 row vector
%     
%     % Update the structure
%     myCamParams{i}.r = corrected_r;
%     myCamParams{i}.t = corrected_t;
%     
%     % Optional: Log the change for one camera
%     % if i == 1 
%     %    fprintf('  Camera %d Original r:\n', i); disp(original_r);
%     %    fprintf('  Camera %d Corrected r:\n', i); disp(corrected_r);
%     %    fprintf('  Camera %d Original t:\n', i); disp(original_t);
%     %    fprintf('  Camera %d Corrected t:\n', i); disp(corrected_t);
%     % end
% end
% fprintf('Corrective transformation applied.\n');
% -----------------------------------------------------

% --- BEGIN LOGGING DATA PASSED TO Label3D ---
fprintf('\n--- Verifying Data Structure Passed to Label3D ---\n');
for i = 1:numCameras
    camName = labelingCameraNames{i};
    fprintf('  Camera %s (Index %d) Data:\n', camName, i);
    fprintf('    myCamParams{%d}.r:\n', i);
    disp(myCamParams{i}.r);
    fprintf('    myCamParams{%d}.t:\n', i);
    disp(myCamParams{i}.t);
end
fprintf('--- End Data Verification ---\n\n');
% --- END LOGGING DATA PASSED TO Label3D ---

% =========================================================================
% --- Load and Prepare Skeleton ---
% =========================================================================
fprintf('Loading and preparing skeleton...\n');

if ~exist(skeletonFile, 'file')
    error('Skeleton file not found: %s. Did create_coco_skeleton.py run correctly?', skeletonFile);
end
baseSkeletonData = load(skeletonFile);

% The loaded baseSkeletonData struct already has the required fields
fprintf('  Base skeleton loaded with %d joints.\n', numel(baseSkeletonData.joint_names));

% Create the multi-animal skeleton
fprintf('  Creating skeleton for %d animals...\n', nAnimals);
try
    % Pass the loaded struct directly
    multiAnimalSkel = multiAnimalSkeleton(baseSkeletonData, nAnimals);
catch ME
    if strcmp(ME.identifier, 'MATLAB:UndefinedFunction')
        error('multiAnimalSkeleton function not found. Ensure multiAnimalSkeleton.m is on the MATLAB path.');
    else
        rethrow(ME);
    end
end
fprintf('  Multi-animal skeleton created with %d total joints.\n', numel(multiAnimalSkel.joint_names));


% =========================================================================
% --- Load Video Frames ---
% =========================================================================

% --- Check for Cached Video Frames ---
videos = cell(numCameras, 1);
usedCache = false;
cacheFilename = '';
if enableVideoCache
    if ~exist(labelingOutputDir, 'dir')
       fprintf('Creating labeling output directory: %s\n', labelingOutputDir);
       mkdir(labelingOutputDir);
    end
    % Make cache filename dependent on the *actual* number of frames being loaded
    cacheFilename = fullfile(labelingOutputDir, sprintf('frameCache_n%d.mat', nFramesToLabel));
    if exist(cacheFilename, 'file')
        fprintf('Attempting to load video frames from cache: %s\n', cacheFilename);
        try
            cacheData = load(cacheFilename, 'videos', 'cachedFramesToLabelIndices', 'cachedVideoPaths');
            % Validate cache
            if isequal(cacheData.cachedFramesToLabelIndices, framesToLabelIndices) && ...
               isequal(cacheData.cachedVideoPaths, videoPaths) && ...
               numel(cacheData.videos) == numCameras && ...
               ~isempty(cacheData.videos) && ... % Ensure videos cell is not empty
               (isempty(framesToLabelIndices) || (numel(cacheData.videos{1}) > 0 && size(cacheData.videos{1}, 4) == nFramesToLabel)) % Check frame count if > 0
                fprintf('  Cache valid. Loading frames from cache...\n');
                videos = cacheData.videos;
                usedCache = true;
            else
                fprintf('  Cache invalid (parameters changed). Reloading frames.\n');
            end
        catch ME
             fprintf('  Error loading cache file: %s. Reloading frames.\n', ME.message);
        end
    end
end

% --- Load Frames if Cache Not Used ---
if ~usedCache
    if nFramesToLabel == 0
        fprintf('No frames selected to load (nFramesToLabel = 0). Skipping frame loading.\n');
        % Ensure 'videos' is a cell array of the correct size, even if empty
        videos = cell(numCameras, 1);
        for i=1:numCameras
            videos{i} = zeros(0,0,3,0,'uint8'); % Empty video data structure
        end
    else
        fprintf('Loading %d frames for each of %d videos...\n', nFramesToLabel, numCameras);
        videoHeight = 0; % Initialize
        videoWidth = 0;

        % Check if Parallel Computing Toolbox is available and user wants it
        canUseParallel = false;
        if useParallel
            if license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel'))
                canUseParallel = true;
                fprintf('  Parallel Computing Toolbox detected. Using parfor.\n');
            else
                fprintf('  Parallel Computing Toolbox not found or license unavailable. Using regular for loop.\n');
            end
        else
             fprintf('  Parallel processing disabled by user. Using regular for loop.\n');
        end

        startTime = tic;

        % Use parfor if enabled and available, otherwise use regular for
        if canUseParallel
            pool = gcp('nocreate'); % Get current pool without creating one
            if isempty(pool)
                parpool(); % Start a default parallel pool
            end
            parfor i = 1:numCameras
                fprintf('  Processing video %d: %s\n', i, videoPaths{i});
                vr = VideoReader(videoPaths{i});
                % Preallocate array for frames (get Height/Width inside parfor)
                videoData = zeros(vr.Height, vr.Width, 3, nFramesToLabel, 'uint8');
                for j = 1:nFramesToLabel
                    frameIdx = framesToLabelIndices(j);
                     % Check if frame index is valid (should be fine now, but keep for safety)
                    if frameIdx > vr.NumFrames
                         warning('Frame index %d exceeds total frames (%d) in video %d. Skipping frame.', frameIdx, vr.NumFrames, i);
                         % Fill with zeros or handle appropriately
                         videoData(:,:,:,j) = 0; % Or consider NaN if using double/single
                    else
                        % Read the specific frame
                        try
                            % Use read() for specific frames - might be slower than readFrame in loop
                            tempFrame = read(vr, frameIdx);
                            videoData(:,:,:,j) = tempFrame;
                        catch ME_read
                             warning('Error reading frame %d from video %d: %s. Skipping frame.', frameIdx, i, ME_read.message);
                             videoData(:,:,:,j) = 0;
                        end
                    end
                end
                videos{i} = videoData;
                fprintf('  Finished processing video %d.\n', i);
            end % end parfor
        else % Use regular for loop
            for i = 1:numCameras
                fprintf('  Processing video %d: %s\n', i, videoPaths{i});
                vr = VideoReader(videoPaths{i});
                if i == 1 % Get dimensions from first video
                    videoHeight = vr.Height;
                    videoWidth = vr.Width;
                elseif isempty(videoHeight) || videoHeight==0 % Handle case where first video failed
                     videoHeight = vr.Height;
                     videoWidth = vr.Width;
                end
                % Preallocate array for frames
                videoData = zeros(videoHeight, videoWidth, 3, nFramesToLabel, 'uint8');
                for j = 1:nFramesToLabel
                    frameIdx = framesToLabelIndices(j);
                     if frameIdx > vr.NumFrames
                         warning('Frame index %d exceeds total frames (%d) in video %d. Skipping frame.', frameIdx, vr.NumFrames, i);
                         videoData(:,:,:,j) = 0;
                    else
                         try
                            tempFrame = read(vr, frameIdx);
                            videoData(:,:,:,j) = tempFrame;
                         catch ME_read
                             warning('Error reading frame %d from video %d: %s. Skipping frame.', frameIdx, i, ME_read.message);
                             videoData(:,:,:,j) = 0;
                         end
                    end
                    if mod(j, 50) == 0 % Print progress periodically
                        fprintf('    Video %d: Loaded frame %d of %d\n', i, j, nFramesToLabel);
                    end
                end
                videos{i} = videoData;
                 fprintf('  Finished processing video %d.\n', i);
            end % end for
        end % end if canUseParallel

        elapsedTime = toc(startTime);
        fprintf('Finished loading all frames in %.2f seconds.\n', elapsedTime);
    end % end if nFramesToLabel > 0

    % --- Cache Video Frames ---
    if enableVideoCache && ~isempty(cacheFilename) && nFramesToLabel > 0 % Only save cache if frames were loaded
        fprintf('Saving loaded frames to cache: %s\n', cacheFilename);
        cachedFramesToLabelIndices = framesToLabelIndices; % Use the potentially adjusted indices
        cachedVideoPaths = videoPaths;
        try
            save(cacheFilename, 'videos', 'cachedFramesToLabelIndices', 'cachedVideoPaths', '-v7.3');
            fprintf('  Successfully saved frame cache.\n');
        catch ME_save
            fprintf('  Error saving frame cache: %s\n', ME_save.message);
        end
    elseif enableVideoCache && nFramesToLabel == 0
         fprintf('Skipping saving cache as no frames were loaded.\n');
    end
end % end if ~usedCache


% =========================================================================
% --- Launch Label3D ---
% =========================================================================
fprintf('Launching Label3D GUI...\n');

% Ensure the output directory exists for saving sessions
if ~exist(labelingOutputDir, 'dir')
   mkdir(labelingOutputDir);
end

if nFramesToLabel == 0
   warning('No frames were loaded. Cannot launch Label3D GUI.');
else
    try
        labelGui = Label3D(myCamParams, videos, multiAnimalSkel, ...
            'framesToLabel', framesToLabelIndices, ...
            'savePath', labelingOutputDir, ...
            'cameraNames', labelingCameraNames, ...
            'camPrefixMap', camNameToPrefixMap, ...
            'undistortedImages', true);

        fprintf('\nLabel3D GUI is running. Close the GUI window to end the session.\n');
        fprintf('Remember to use Shift+S within the GUI to save your progress frequently!\n');
        fprintf('Saved sessions will appear in: %s\n', labelingOutputDir);

        % Optional: Wait for the GUI figure to be closed before script ends
        % uiwait(labelGui.Parent);
        % fprintf('Label3D GUI closed.\n');

    catch ME
        fprintf('\nError launching or running Label3D:\n');
        fprintf('%s\n', ME.getReport());
        fprintf('Please check paths, dependencies, and input data.\n');
    end
end % end if nFramesToLabel > 0