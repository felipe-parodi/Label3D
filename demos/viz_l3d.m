%% viz_l3d.m
% Script to load a saved Label3D session and generate a video of the 3D labels.

clear all;
close all;
clc;

% --- User Configuration ---
% Path to the Label3D output .mat file you want to visualize
label3d_output_mat_file = 'A:\\EnclosureProjects\\inprep\\freemat\\code\\calibration\\WMcalibration\\Label3D\\labeling_output\\20250520_224541_Label3D.mat'; % EXAMPLE, PLEASE CHANGE

% Output video file path and name
output_video_file = 'A:\\EnclosureProjects\\inprep\\freemat\\code\\calibration\\WMcalibration\\Label3D\\labeling_output\\visualization_video.mp4'; % EXAMPLE, PLEASE CHANGE

% --- Paths for dependent data (these should match your freemat_run_label3d.m setup for the session) ---
% Directory containing the ORIGINAL video files (used for deriving calib paths if not using cropped)
originalVideoDir_config = "A:\\EnclosureProjects\\inprep\\freemat\\data\\experiments\\good\\240528\\video\\experiment\\fixed_timestamp"; % EXAMPLE, PLEASE CHANGE

% Directory containing the CROPPED videos (if the session used them)
cropVideoDir_config = "A:\\EnclosureProjects\\inprep\\freemat\\data\\experiments\\good\\240528\\video\\experiment\\fixed_timestamp\\crop1min_cropped_videos"; % EXAMPLE, PLEASE CHANGE

% Set to true if the Label3D session was created using CROPPED videos from cropVideoDir_config
% Set to false if the Label3D session was created using ORIGINAL videos from originalVideoDir_config
use_cropped_videos_for_viz = true; % PLEASE VERIFY AND CHANGE IF NEEDED

% Directory containing camera calibration *_params.mat files
% This path should be absolute or relative to the Label3D root directory.
% E.g., fullfile(fileparts(mfilename('fullpath')), '..', 'label3d_params') if they are in Label3D/label3d_params
% Or an absolute path like "A:\\..."
paramDir_config = "A:\\EnclosureProjects\\inprep\\freemat\\data\\experiments\\good\\240528\\video\\calibration\\fixed_timestamp\\multical\\label3d"; % EXAMPLE, PLEASE CHANGE

% Video reading settings
enableVideoCacheForViz = true;   % Enable caching of loaded frames for this script
useParallelForViz = true;        % Use Parallel Computing Toolbox for loading frames if available

% Video output settings
output_fps = 30;
output_quality = 75; % For MP4, typically 0-100, higher is better. For 'Motion JPEG AVI', 1-100 (75 is default good).

% --- End User Configuration ---

fprintf('Starting Label3D Visualization Script...\n');

% --- Add necessary paths ---
script_base_path = fileparts(mfilename('fullpath'));
addpath(fullfile(script_base_path, '..')); % Add Label3D root
addpath(genpath(fullfile(script_base_path, '..', 'deps'))); % Add dependencies

% --- 1. Load Label3D Output File ---
if ~exist(label3d_output_mat_file, 'file')
    error('Label3D output file not found: %s', label3d_output_mat_file);
end
fprintf('Loading Label3D data from: %s\n', label3d_output_mat_file);
loaded_data = load(label3d_output_mat_file);

% Extract essential data
points3D_from_mat      = loaded_data.data_3D;      % nMarkers x 3 x nLabelSessionFrames
framesToLabel_from_mat = loaded_data.framesToLabel; % Original frame numbers from video
session_skeleton       = loaded_data.skeleton;      % Multi-animal skeleton structure
session_cameraNames    = loaded_data.cameraNamesToSave;   % Cell array of camera names used in session
session_nAnimals       = loaded_data.nAnimalsInSession;
% session_imageSize      = loaded_data.imageSize; % nCams x 2 [H, W] - might be useful if videos frames are not full size
labelingOutputDir_from_mat = fileparts(label3d_output_mat_file); % For cache location

if isempty(framesToLabel_from_mat)
    error('No frames were labeled in the provided Label3D session file. Cannot generate video.');
end
fprintf('  Loaded data for %d animals, %d cameras, and %d labeled frames.\n', ...
    session_nAnimals, numel(session_cameraNames), numel(framesToLabel_from_mat));

% --- 2. Determine Video Source and Calibration Paths ---
if use_cropped_videos_for_viz
    videoSourceDir = cropVideoDir_config;
    fprintf('Using CROPPED videos from directory: %s\n', videoSourceDir);
else
    videoSourceDir = originalVideoDir_config;
    fprintf('Using ORIGINAL videos from directory: %s\n', videoSourceDir);
    
    % Derive calibration paths from the ORIGINAL video directory (as in freemat_run_label3d.m)
    [baseVideoPath_temp, ~, ~] = fileparts(originalVideoDir_config);
    [baseVideoPath_temp, ~, ~] = fileparts(baseVideoPath_temp); % Go up two levels
    calibrationBaseDir = fullfile(baseVideoPath_temp, 'calibration', 'fixed_timestamp', 'multical');
    extractionReportPath = fullfile(calibrationBaseDir, 'extraction_report.txt');
    
    if ~exist(extractionReportPath, 'file')
        error('Extraction report file not found (needed for original video names): %s', extractionReportPath);
    end
    fprintf('Parsing extraction report: %s\n', extractionReportPath);
    camNameToPrefixMap = containers.Map('KeyType', 'char', 'ValueType', 'char');
    fid = fopen(extractionReportPath, 'r');
    if fid == -1, error('Could not open extraction report file: %s', extractionReportPath); end
    regexPattern = 'Camera:\\s+(\\w{7}).*\\((Cam_\\d{3})\\)'; % Capture prefix and Cam_XXX
    tline = fgetl(fid);
    while ischar(tline)
        tokens = regexp(tline, regexPattern, 'tokens');
        if ~isempty(tokens), camNameToPrefixMap(tokens{1}{2}) = tokens{1}{1}; end
        tline = fgetl(fid);
    end
    fclose(fid);
    fprintf('  Found mappings for %d cameras in the report.\n', length(keys(camNameToPrefixMap)));
end

if ~exist(videoSourceDir, 'dir')
    error('Video source directory not found: %s', videoSourceDir);
end
paramDir = paramDir_config;
if ~exist(paramDir, 'dir')
    error('Camera parameter directory not found: %s', paramDir);
end

% --- 3. Load Camera Parameters for the Session Cameras ---
num_session_cameras = numel(session_cameraNames);
myCamParams_for_viz = cell(num_session_cameras, 1);
fprintf('Loading camera parameters for %d session cameras...\n', num_session_cameras);
for i = 1:num_session_cameras
    camName = session_cameraNames{i};
    paramFile = fullfile(paramDir, camName + "_params.mat");
    if ~exist(paramFile, 'file')
        error('Parameter file not found for camera %s: %s', camName, paramFile);
    end
    % fprintf('  Loading params for %s from %s\n', camName, paramFile);
    myCamParams_for_viz{i} = load(paramFile);
end
fprintf('Successfully loaded parameters for all session cameras.\n');

% --- 4. Get Video Paths for the Session Cameras ---
videoPaths_for_session = cell(num_session_cameras, 1);
fprintf('Determining video paths for session cameras...\n');
for i = 1:num_session_cameras
    currentCamName = session_cameraNames{i};
    foundMatch = false;
    matchedFile = '';

    if use_cropped_videos_for_viz
        expectedFilename = currentCamName + ".mp4";
        expectedFullPath = fullfile(videoSourceDir, expectedFilename);
        if exist(expectedFullPath, 'file')
            matchedFile = expectedFilename;
            foundMatch = true;
        else
            % Try .avi as a fallback for cropped videos
            expectedFilename = currentCamName + ".avi";
            expectedFullPath = fullfile(videoSourceDir, expectedFilename);
            if exist(expectedFullPath, 'file')
                 matchedFile = expectedFilename;
                 foundMatch = true;
            end
        end
    else % Using original videos, requires prefix map
        if ~isKey(camNameToPrefixMap, currentCamName)
            error('Camera name %s (from .mat file) not found in extraction report. Cannot find original video.', currentCamName);
        end
        prefix = camNameToPrefixMap(currentCamName);
        potentialVideoFiles = dir(fullfile(videoSourceDir, [prefix, '*.mp4']));
        if isempty(potentialVideoFiles)
            potentialVideoFiles = dir(fullfile(videoSourceDir, [prefix, '*.avi'])); % Fallback to .avi
        end
        
        if numel(potentialVideoFiles) == 1
            matchedFile = potentialVideoFiles(1).name;
            foundMatch = true;
        elseif numel(potentialVideoFiles) > 1
            warning('Ambiguous match for original video for %s with prefix %s. Found multiple files. Using the first one: %s', currentCamName, prefix, potentialVideoFiles(1).name);
            % For visualization, we might proceed with the first, but this is a warning.
            matchedFile = potentialVideoFiles(1).name; 
            foundMatch = true; 
        end
    end

    if foundMatch && ~isempty(matchedFile)
        videoPaths_for_session{i} = fullfile(videoSourceDir, matchedFile);
        fprintf('  Found video for %s: %s\n', currentCamName, videoPaths_for_session{i});
    else
        error('Could not find video file for camera %s in %s.', currentCamName, videoSourceDir);
    end
end
fprintf('Successfully determined all video paths for the session.\n');

% --- 5. Load Video Frames ---
nFramesToLoadForViz = numel(framesToLabel_from_mat);
videos_for_view3d = cell(num_session_cameras, 1);
usedCacheForViz = false;
cacheFilenameForViz = '';

if enableVideoCacheForViz
    % Create a more specific cache name to avoid conflicts
    cacheIdentifier = sprintf('viz_n%d_fStart%d_fEnd%d_cams%d', ...
                              nFramesToLoadForViz, framesToLabel_from_mat(1), framesToLabel_from_mat(end), num_session_cameras);
    % Hash the camera names and video paths for more robust caching against path changes
    % For simplicity here, using a basic identifier. Consider crypto hash for production.
    pathHash = ''; % Ensure it starts as a char array for string concatenation
    for p_idx = 1:numel(videoPaths_for_session)
        if ischar(videoPaths_for_session{p_idx}) % Ensure it is a char array before concatenating
            pathHash = [pathHash, videoPaths_for_session{p_idx}]; %#ok<AGROW>
        end
    end
    % Convert pathHash to a simple numeric hash if possible, or use a portion of it.
    % This is a rudimentary way to include path info in cache name.
    % A proper hash function (e.g., from Java via MATLAB) would be better.
    if exist('OCTAVE_VERSION', 'builtin') == 0 && exist('DataHash','file') % Check for DataHash on MATLAB
        try
            pathHashShort = DataHash(pathHash); % Requires DataHash from FileExchange
             cacheIdentifier = [cacheIdentifier, '_', pathHashShort(1:8)];
        catch
            % fallback if DataHash not available or errors
             pathHashShort = sum(uint8(pathHash)); % very simple checksum
             cacheIdentifier = [cacheIdentifier, '_', num2str(pathHashShort)];
        end
    else % Octave or DataHash not available
        pathHashShort = sum(uint8(pathHash)); % very simple checksum
        cacheIdentifier = [cacheIdentifier, '_', num2str(pathHashShort)];
    end

    cacheFilenameForViz = fullfile(labelingOutputDir_from_mat, ['frameCache_', cacheIdentifier, '.mat']);
    
    if exist(cacheFilenameForViz, 'file')
        fprintf('Attempting to load video frames from VIZ cache: %s\n', cacheFilenameForViz);
        try
            cacheData = load(cacheFilenameForViz, 'videos_for_view3d_cached', 'cachedFramesToLabelIndices', 'cachedVideoPaths');
            if isequal(cacheData.cachedFramesToLabelIndices, framesToLabel_from_mat) && ...
               isequal(cacheData.cachedVideoPaths, videoPaths_for_session) && ...
               numel(cacheData.videos_for_view3d_cached) == num_session_cameras && ...
               ~isempty(cacheData.videos_for_view3d_cached) && ...
               (isempty(framesToLabel_from_mat) || (numel(cacheData.videos_for_view3d_cached{1}) > 0 && size(cacheData.videos_for_view3d_cached{1}, 4) == nFramesToLoadForViz))
                fprintf('  VIZ Cache valid. Loading frames from cache...\n');
                videos_for_view3d = cacheData.videos_for_view3d_cached;
                usedCacheForViz = true;
            else
                fprintf('  VIZ Cache invalid (parameters changed or mismatch). Reloading frames.\n');
            end
        catch ME_load_cache
             fprintf('  Error loading VIZ cache file: %s. Reloading frames.\n', ME_load_cache.message);
        end
    end
end

if ~usedCacheForViz
    if nFramesToLoadForViz == 0
        fprintf('No frames to load (nFramesToLoadForViz = 0). Skipping frame loading.\n');
        for i=1:num_session_cameras, videos_for_view3d{i} = zeros(0,0,3,0,'uint8'); end
    else
        fprintf('Loading %d frames for each of %d videos for visualization...\n', nFramesToLoadForViz, num_session_cameras);
        
        canUseParallelForViz = false;
        if useParallelForViz
            if license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel'))
                canUseParallelForViz = true;
                fprintf('  Parallel Computing Toolbox detected. Using parfor for VIZ frame loading.\n');
            else
                fprintf('  Parallel Computing Toolbox not found or license unavailable for VIZ. Using regular for loop.\n');
            end
        else
             fprintf('  Parallel processing disabled by user for VIZ. Using regular for loop.\n');
        end

        startTimeLoad = tic;
        if canUseParallelForViz
            pool = gcp('nocreate'); if isempty(pool), parpool(); end
            parfor i = 1:num_session_cameras
                fprintf('  VIZ Processing video %d: %s\n', i, videoPaths_for_session{i});
                vr = VideoReader(videoPaths_for_session{i});
                % Determine video dimensions from the first frame of the first video if possible
                % For parfor, each worker needs to determine its own video's dimensions
                % tempFrameTest = read(vr, framesToLabel_from_mat(1)); % Read first relevant frame
                % videoData = zeros(size(tempFrameTest,1), size(tempFrameTest,2), 3, nFramesToLoadForViz, 'uint8');
                % Re-initialize vr if read changes state needed for subsequent reads, or use vr.Height, vr.Width
                videoData = zeros(vr.Height, vr.Width, 3, nFramesToLoadForViz, 'uint8');

                for j = 1:nFramesToLoadForViz
                    frameIdx = framesToLabel_from_mat(j);
                    if frameIdx > vr.NumFrames
                         warning('VIZ: Frame index %d exceeds total frames (%d) in video %d. Storing blank frame.', frameIdx, vr.NumFrames, i);
                         videoData(:,:,:,j) = 0; % Store blank frame
                    else
                        try
                            videoData(:,:,:,j) = read(vr, frameIdx);
                        catch ME_read_frame
                             warning('VIZ: Error reading frame %d from video %d: %s. Storing blank frame.', frameIdx, i, ME_read_frame.message);
                             videoData(:,:,:,j) = 0; % Store blank frame
                        end
                    end
                end
                videos_for_view3d{i} = videoData;
                fprintf('  VIZ Finished processing video %d.\n', i);
            end
        else % Regular for loop
            tempVideoHeight = 0; tempVideoWidth = 0; % Initialize
            for i = 1:num_session_cameras
                fprintf('  VIZ Processing video %d: %s\n', i, videoPaths_for_session{i});
                vr = VideoReader(videoPaths_for_session{i});
                if i == 1 % Get dimensions from first video
                    tempVideoHeight = vr.Height;
                    tempVideoWidth = vr.Width;
                end
                videoData = zeros(tempVideoHeight, tempVideoWidth, 3, nFramesToLoadForViz, 'uint8');
                for j = 1:nFramesToLoadForViz
                    frameIdx = framesToLabel_from_mat(j);
                     if frameIdx > vr.NumFrames
                         warning('VIZ: Frame index %d exceeds total frames (%d) in video %d. Storing blank frame.', frameIdx, vr.NumFrames, i);
                         videoData(:,:,:,j) = 0;
                    else
                        try
                            videoData(:,:,:,j) = read(vr, frameIdx);
                        catch ME_read_frame
                             warning('VIZ: Error reading frame %d from video %d: %s. Storing blank frame.', frameIdx, i, ME_read_frame.message);
                             videoData(:,:,:,j) = 0;
                        end
                    end
                end
                videos_for_view3d{i} = videoData;
                fprintf('  VIZ Finished processing video %d.\n', i);
            end
        end
        elapsedTimeLoad = toc(startTimeLoad);
        fprintf('Finished loading all frames for VIZ in %.2f seconds.\n', elapsedTimeLoad);

        if enableVideoCacheForViz && ~isempty(cacheFilenameForViz) && nFramesToLoadForViz > 0
            fprintf('Saving loaded frames to VIZ cache: %s\n', cacheFilenameForViz);
            videos_for_view3d_cached = videos_for_view3d; % Variables to save
            cachedFramesToLabelIndices = framesToLabel_from_mat;
            cachedVideoPaths = videoPaths_for_session;
            try
                save(cacheFilenameForViz, 'videos_for_view3d_cached', 'cachedFramesToLabelIndices', 'cachedVideoPaths', '-v7.3');
                fprintf('  Successfully saved VIZ frame cache.\n');
            catch ME_save_cache
                fprintf('  Error saving VIZ frame cache: %s\n', ME_save_cache.message);
            end
        end
    end
end

% --- 6. Prepare 3D Points for View3D.loadFrom3D() ---
% Label3D stores points3D as (nMarkers x 3 x nFrames)
% View3D's loadFrom3D expects (nFrames x 3 x nMarkers) or (nFrames x nMarkers x 3)
% We will provide (nFrames x 3 x nMarkers)
nMarkers_total_from_skeleton = numel(session_skeleton.joint_names);
if nMarkers_total_from_skeleton == 0 && session_nAnimals > 0
    warning('Skeleton from .mat file has 0 markers (joint_names), but session_nAnimals is %d. Video might be empty or show no keypoints.', session_nAnimals);
    % Attempt to infer nMarkers if points3D_from_mat is populated and skeleton is not
    if ndims(points3D_from_mat) == 3 && size(points3D_from_mat,2) == 3
        nMarkers_total_from_skeleton = size(points3D_from_mat,1);
        warning('Inferring nMarkers_total = %d from points3D_from_mat dimensions as skeleton was empty.', nMarkers_total_from_skeleton);
    elseif ndims(points3D_from_mat) == 2 && mod(size(points3D_from_mat,2),3)==0
        nMarkers_total_from_skeleton = size(points3D_from_mat,2)/3;
        warning('Inferring nMarkers_total = %d from 2D points3D_from_mat dimensions as skeleton was empty.', nMarkers_total_from_skeleton);
    else
        nMarkers_total_from_skeleton = 0; % Cannot infer
    end
end

% --- Process points3D_from_mat (loaded_data.data_3D) ---
temp_points3D = points3D_from_mat; % This is loaded_data.data_3D
actual_loaded_frames = 0;

if nMarkers_total_from_skeleton > 0
    if ndims(temp_points3D) == 2 && size(temp_points3D, 2) == (nMarkers_total_from_skeleton * 3)
        % Likely (nActualFrames, nMarkers * 3)
        actual_loaded_frames = size(temp_points3D, 1);
        if actual_loaded_frames > 0
            fprintf('  Input data_3D appears to be (%d frames x %d markers*3 coords). Reshaping...\n', actual_loaded_frames, nMarkers_total_from_skeleton);
            temp_points3D = reshape(temp_points3D', 3, nMarkers_total_from_skeleton, actual_loaded_frames); % to (3, nMarkers, nFrames)
            temp_points3D = permute(temp_points3D, [2 1 3]); % to (nMarkers, 3, nFrames)
        else
            temp_points3D = NaN(nMarkers_total_from_skeleton, 3, 0); % No frames, but keep structure
        end
    elseif ndims(temp_points3D) == 3 && size(temp_points3D, 1) == nMarkers_total_from_skeleton && size(temp_points3D, 2) == 3
        % Already (nMarkers, 3, nActualFrames)
        actual_loaded_frames = size(temp_points3D, 3);
        fprintf('  Input data_3D appears to be (%d markers x 3 coords x %d frames). Using as is before padding.\n', nMarkers_total_from_skeleton, actual_loaded_frames);
    elseif ndims(temp_points3D) == 2 && size(temp_points3D,1) == nMarkers_total_from_skeleton && size(temp_points3D,2) == 3 && nFramesToLoadForViz == 1
        % Case: (nMarkers, 3) for a single frame session saved without the 3rd dim
        actual_loaded_frames = 1;
        fprintf('  Input data_3D appears to be (%d markers x 3 coords) for a single frame. Adding frame dimension.\n', nMarkers_total_from_skeleton);
        temp_points3D = reshape(temp_points3D, [nMarkers_total_from_skeleton, 3, 1]);
    else
        warning('Dimensions of loaded data_3D (%s) are unexpected given nMarkers_from_skeleton=%d. May lead to errors.', mat2str(size(temp_points3D)), nMarkers_total_from_skeleton);
        % Attempt to get actual_loaded_frames if it has 3 dims, otherwise assume 0 or 1 if 2D
        if ndims(temp_points3D) == 3
            actual_loaded_frames = size(temp_points3D,3);
        elseif ndims(temp_points3D) == 2 && ~isempty(temp_points3D)
            actual_loaded_frames = 1; % Best guess for 2D non-empty data
        else 
            actual_loaded_frames = 0;
        end
        if actual_loaded_frames == 0 && nFramesToLoadForViz > 0 && nMarkers_total_from_skeleton > 0
             temp_points3D = NaN(nMarkers_total_from_skeleton, 3, 0); % Ensure it has 3 dims for padding logic
        end
    end
else % nMarkers_total_from_skeleton is 0
    warning('Cannot determine nMarkers from skeleton. Assuming data_3D is empty or has 0 markers.');
    temp_points3D = NaN(0, 3, nFramesToLoadForViz); % Default to empty compatible array
    actual_loaded_frames = 0; % Or try to get from temp_points3D if it's not truly empty
    if ndims(points3D_from_mat) == 3, actual_loaded_frames = size(points3D_from_mat,3); 
    elseif ~isempty(points3D_from_mat), actual_loaded_frames = 1; end

end

% Pad to nFramesToLoadForViz (session total frames)
final_points3D_for_session = NaN(nMarkers_total_from_skeleton, 3, nFramesToLoadForViz);

if actual_loaded_frames > nFramesToLoadForViz
    warning('Loaded data_3D has MORE frames (%d) than framesToLabel in session (%d). Truncating.', actual_loaded_frames, nFramesToLoadForViz);
    if nMarkers_total_from_skeleton > 0
        final_points3D_for_session = temp_points3D(:,:,1:nFramesToLoadForViz);
    end
elsif actual_loaded_frames < nFramesToLoadForViz
    if actual_loaded_frames > 0
        warning('Loaded data_3D has FEWER frames (%d) than framesToLabel in session (%d). Padding with NaNs.', actual_loaded_frames, nFramesToLoadForViz);
        if nMarkers_total_from_skeleton > 0
            final_points3D_for_session(:,:,1:actual_loaded_frames) = temp_points3D(:,:,1:actual_loaded_frames);
        end
    elseif nFramesToLoadForViz > 0 % actual_loaded_frames is 0, but session expects frames
        warning('Loaded data_3D has 0 frames, but session expects %d frames. Using all NaNs.', nFramesToLoadForViz);
        % final_points3D_for_session is already all NaNs
    end
else % actual_loaded_frames == nFramesToLoadForViz
    if nMarkers_total_from_skeleton > 0
        final_points3D_for_session = temp_points3D;
    end
    fprintf('  Loaded data_3D has matching number of frames (%d) as session framesToLabel.\n', actual_loaded_frames);
end

points3D_for_viewgui = permute(final_points3D_for_session, [3 2 1]); % Reshape to nFrames x 3 x nMarkers
fprintf('Reshaped points3D from [%d x %d x %d] to [%d x %d x %d] for View3D.\n', ...
    size(final_points3D_for_session,1), size(final_points3D_for_session,2), size(final_points3D_for_session,3), ...
    size(points3D_for_viewgui,1), size(points3D_for_viewgui,2), size(points3D_for_viewgui,3));
    
% --- 7. Initialize View3D ---
fprintf('Initializing View3D...\n');
% Ensure videos_for_view3d has some content if frames were expected
if nFramesToLoadForViz > 0 && isempty(videos_for_view3d{1})
    error('Video frames cell array is unexpectedly empty for View3D initialization despite frames being requested.');
end

% Check if UndistortedImages and FlipViewsVertically are stored in loaded_data.params
% Defaulting to true as per freemat_run_label3d common settings
undistortFlag = true;
flipViewsFlag = true;
if isfield(loaded_data, 'params') && ~isempty(loaded_data.params) % params saved by Label3D are the camParams directly
    % This part is tricky: Label3D saves the *actual camera parameters used*, not the boolean flags.
    % The flags 'undistortedImages' and 'flipViewsVertically' are properties of the Label3D/View3D GUI object itself.
    % We assume they were true during labeling, as per typical use in freemat_run_label3d.m.
    % If these were configurable and saved in the .mat, we'd load them here.
    % For now, assume 'true' as commonly used.
end
% Check if 'imageSize' was saved by Label3D; it could be passed to View3D
view3D_options = {
    'framesToLabel', framesToLabel_from_mat, ...
    'cameraNames', session_cameraNames, ...
    'undistortedImages', undistortFlag, ...
    'flipViewsVertically', flipViewsFlag, ...
    'nAnimals', session_nAnimals
};
if isfield(loaded_data, 'imageSize') && ~isempty(loaded_data.imageSize)
    view3D_options = [view3D_options, {'imageSize', loaded_data.imageSize}];
end


viewGui = View3D(myCamParams_for_viz, videos_for_view3d, session_skeleton, view3D_options{:});

% --- 8. Load Points and Generate Video ---
fprintf('Loading 3D points into View3D...\n');
viewGui.loadFrom3D(points3D_for_viewgui);

output_dir = fileparts(output_video_file);
if ~exist(output_dir, 'dir')
    fprintf('Output directory %s does not exist, creating it...\n', output_dir);
    mkdir(output_dir);
end

fprintf('Generating video of all %d labeled frames to: %s\n', nFramesToLoadForViz, output_video_file);
frames_to_render_in_video = 1:nFramesToLoadForViz; % These are indices into the loaded video sequence in View3D

% Check if output_video_file ends with .gif for specific writer
[~,~,ext] = fileparts(output_video_file);
if strcmpi(ext, '.gif')
    % Animator.writeVideo uses write_frames, which uses VideoWriter for mp4/avi,
    % and a different path for gifs (imwritemulti).
    % FPS for gif is handled by 'DelayTime' -> 1/FPS
    fprintf('  Generating GIF with FPS approx %d (DelayTime %f)\n', output_fps, 1/output_fps);
    viewGui.writeVideo(frames_to_render_in_video, output_video_file, 'DelayTime', 1/output_fps);
else
    % For .mp4 or .avi
    viewGui.writeVideo(frames_to_render_in_video, output_video_file, 'FPS', output_fps, 'Quality', output_quality);
end

fprintf('Video generation complete: %s\n', output_video_file);
fprintf('Visualization script finished.\n');

% Optionally, make the GUI visible if you want to inspect before closing
% uiwait(viewGui.Parent); % This would pause script until GUI is closed

% Clean up GUI if not needed further
if isvalid(viewGui) && isgraphics(viewGui.Parent)
    close(viewGui.Parent);
end
