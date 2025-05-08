%% plot_pp.m
% Script to visualize the principal point from a camera parameters file
% onto the first frame of an automatically discovered video.

clear all;
close all;
clc;

% --- USER: Define Target and Paths --- 

targetCamName = "Cam_002"; % Specify the camera name you want to visualize

% Define base directories (Adjust these paths as needed)
% Directory containing the video files (e.g., calibration or experiment videos)
videoDir = "A:\EnclosureProjects\inprep\freemat\data\experiments\good\240528\video\calibration\fixed_timestamp";

% Base directory for calibration outputs (where extraction_report.txt and label3d/ are)
calibrationBaseDir = "A:\EnclosureProjects\inprep\freemat\data\experiments\good\240528\video\calibration\fixed_timestamp\multical";

% --- Derive Specific File Paths --- 

% Path to the parameter file for the target camera
paramDir = fullfile(calibrationBaseDir, 'label3d');
matFilePath = fullfile(paramDir, sprintf('%s_params.mat', targetCamName));

% Path to the extraction report
extractionReportPath = fullfile(calibrationBaseDir, 'extraction_report.txt');

% --- Check if essential files/dirs exist ---
if ~exist(videoDir, 'dir')
    error('Video directory not found: %s', videoDir);
end
if ~exist(calibrationBaseDir, 'dir')
    error('Calibration base directory not found: %s', calibrationBaseDir);
end
if ~exist(extractionReportPath, 'file')
    error('Extraction report file not found: %s', extractionReportPath);
end
if ~exist(matFilePath, 'file')
    error('MAT parameter file for %s not found: %s', targetCamName, matFilePath);
end

% --- Parse Extraction Report --- 
fprintf('Parsing extraction report: %s\n', extractionReportPath);
camNameToPrefixMap = containers.Map('KeyType', 'char', 'ValueType', 'char');
try
    fid = fopen(extractionReportPath, 'r');
    if fid == -1, error('Could not open extraction report file: %s', extractionReportPath); end
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
    if fid ~= -1, fclose(fid); end
    rethrow(ME);
end
fprintf('Found mappings for %d cameras in the report.\n', length(keys(camNameToPrefixMap)));

% --- Find Video File --- 
fprintf('Searching for video file for %s in directory: %s\n', targetCamName, videoDir);

if ~isKey(camNameToPrefixMap, targetCamName)
    error('Target camera name "%s" not found in extraction report.', targetCamName);
end
prefix = camNameToPrefixMap(targetCamName);

% List potential video files
potentialVideoFiles = dir(fullfile(videoDir, '*.mp4')); % Add other extensions if needed
if isempty(potentialVideoFiles)
    error('No video files found in directory: %s', videoDir);
end

videoFilePath = '';
foundMatch = false;

for j = 1:length(potentialVideoFiles)
    fname = potentialVideoFiles(j).name;
    if startsWith(fname, prefix)
        if foundMatch
            error('Ambiguous match! Found multiple files starting with prefix "%s" for camera %s. Cannot proceed.', prefix, targetCamName);
        else
            videoFilePath = fullfile(videoDir, fname);
            fprintf('  Found video: %s\n', fname);
            foundMatch = true;
            % Continue searching to ensure no ambiguity
        end
    end
end

if ~foundMatch
    error('No video file found for camera %s (prefix: "%s") in %s.', targetCamName, prefix, videoDir);
end

% --- Load Parameters ---
fprintf('Loading camera parameters from: %s\n', matFilePath);
params = load(matFilePath);

% --- Load First Frame of Video ---
fprintf('Loading first frame from video: %s\n', videoFilePath);
try
    vr = VideoReader(videoFilePath);
    if vr.NumFrames == 0
        error('VideoReader reported 0 frames for %s. Check video file.', videoFilePath);
    end
    img = read(vr, 1); % Read the first frame (index 1)
catch ME
    error('Could not read video file %s. Error: %s', videoFilePath, ME.message);
end

% --- Extract Intrinsics and Principal Point ---
if ~isfield(params, 'K')
    error('Parameter file %s does not contain the expected intrinsic matrix ''K''.', matFilePath);
end

K = params.K;

% --- Check K format and extract principal point ---
if all(size(K) == [3, 3]) && K(1,2) == 0 && K(2,1) == 0 && K(3,3) == 1 && K(1,3)~=0 && K(2,3)~=0 && K(3,1)==0 && K(3,2)==0
    % Standard format: [[fx, 0, cx], [0, fy, cy], [0, 0, 1]]
    cx = K(1, 3);
    cy = K(2, 3);
    fprintf('K appears standard [[fx, 0, cx], [0, fy, cy], [0, 0, 1]]. Extracted cx=%.2f, cy=%.2f\n', cx, cy);
else 
    % Add check for the non-standard format plot_pp originally expected
    if all(size(K) == [3, 3]) && K(1,2) == 0 && K(1,3) == 0 && K(2,1) == 0 && K(2,3) == 0 && K(3,3) == 1 && K(3,1)~=0 && K(3,2)~=0
        % Non-standard format: [[fx,0,0],[0,fy,0],[cx,cy,1]]
        cx = K(3, 1);
        cy = K(3, 2);
        fprintf('K appears non-standard [[fx,0,0],[0,fy,0],[cx,cy,1]]. Extracted cx=%.2f, cy=%.2f\n', cx, cy);
    else
        warning('K matrix format in %s is unrecognized. Cannot reliably extract principal point.', matFilePath);
        % Attempt standard extraction as a fallback
        try 
            cx = K(1, 3);
            cy = K(2, 3);
            fprintf('Warning: Unrecognized K format. Attempting standard extraction: cx=%.2f, cy=%.2f\n', cx, cy);
        catch
            error('Failed to extract principal point due to unrecognized K format.');
        end
    end
end

% --- Visualize --- 
figure;
imshow(img);
hold on;

% Plot the principal point (cx, cy)
plot(cx, cy, 'r+', 'MarkerSize', 15, 'LineWidth', 2); % Red cross marker

% Add text label near the point
offset = 15; % Pixel offset for text
text(cx + offset, cy + offset, sprintf('(%.1f, %.1f)', cx, cy), ...
    'Color', 'red', 'FontSize', 12, 'FontWeight', 'bold');

title({sprintf('Principal Point Visualization for %s', targetCamName), ...
      sprintf('Camera Param File: %s', matFilePath), ...
      sprintf('Video File: %s', videoFilePath)}, ...
      'Interpreter', 'none'); % Prevent underscore interpretation

hold off;

fprintf('Visualization complete.\n');

