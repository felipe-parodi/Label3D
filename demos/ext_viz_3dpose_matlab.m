% --- Script Configuration ---
DEMO_MODE = false; % Set to true for DANNCE demo, false for individual Cam_*_params.mat

% --- Visualization Parameters ---
camSize = 50; % Adjusted based on previous findings

% Create figure
figure;
hold on;
grid on;
axis equal; % Essential for correct aspect ratio
xlabel('X (units)'); % Units depend on the .mat file (likely mm)
ylabel('Y (units)');
zlabel('Z (units)');
% Title will be set based on mode

all_t = []; % Initialize for axis limits

if DEMO_MODE
    % --- DANNCE Demo Mode - Single Hypothesis based on Label3D.m source ---
    demoMatFile = "dannce/demo/markerless_mouse_1/label3d_demo.mat";
    fprintf('Loading DANNCE demo data from: %s\n', demoMatFile);
    if ~exist(demoMatFile, 'file'), error('DANNCE demo .mat file not found: %s.', demoMatFile); end
    demoData = load(demoMatFile);
    if ~isfield(demoData, 'params'), error('Demo .mat missing ''params'' field.'); end
    camParamsFromDemo = demoData.params;
    numCamerasInDemo = numel(camParamsFromDemo);
    if numCamerasInDemo == 0, error('No camera parameters in demoData.params.'); end
    
    camNamesFromDemo = {};
    if isfield(demoData, 'camnames') && numel(demoData.camnames) == numCamerasInDemo
        camNamesFromDemo = demoData.camnames;
    else
        warning('camnames mismatch or missing in demo. Using default names.');
        for idx=1:numCamerasInDemo, camNamesFromDemo{idx} = sprintf('DemoCam %d', idx); end
    end
    fprintf('Found %d cameras. Plotting single interpretation based on Label3D.m logic.\n', numCamerasInDemo);

    base_colors = jet(numCamerasInDemo);
    all_calculated_Tcw_for_axis_limits = zeros(3, numCamerasInDemo); % Store calculated T_c_w for axis limits

    fig_h = figure('Name', 'DEMO - Label3D.m Interpretation', 'NumberTitle', 'off');
    hold on; grid on; axis equal;
    xlabel('X'); ylabel('Y'); zlabel('Z');
    title('DANNCE Demo: Label3D.m interpretation (params.r=Rcw, params.t=Twc_col)');

    for i = 1:numCamerasInDemo
        currentCamParams = camParamsFromDemo{i};
        currentCamName = camNamesFromDemo{i};

        if ~isfield(currentCamParams, 'r') || ~isfield(currentCamParams, 't')
            warning('Cam %s params missing r or t. Skipping.', currentCamName);
            all_calculated_Tcw_for_axis_limits(:, i) = NaN;
            continue;
        end
        
        R_cw_dannce = currentCamParams.r; % Label3D assumes this is R_c_w
        T_wc_col_dannce = currentCamParams.t; % Label3D assumes this is T_w_c (col vector)

        % Ensure T_wc_col_dannce is 3x1
        if ~isequal(size(T_wc_col_dannce), [3,1])
            if isequal(size(T_wc_col_dannce), [1,3]) % if it's 1x3, transpose it
                T_wc_col_dannce = T_wc_col_dannce';
                warning('Cam %s params.t was 1x3, transposed to 3x1 for T_w_c_col convention.', currentCamName);
            else
                warning('T_wc for Cam %s not 3x1 or 1x3. Skipping.', currentCamName);
                all_calculated_Tcw_for_axis_limits(:, i) = NaN;
                continue;
            end
        end

        % plotCamera expects:
        %   Orientation = R_w_c
        %   Location    = T_c_w (camera center in world, 1x3 row vector)
        
        Orientation_for_plot = R_cw_dannce'; % R_w_c = R_c_w'
        
        % Location_for_plot = - (T_wc_col_dannce') * (R_cw_dannce');
        % which is T_c_w = -T_w_c_row * R_w_c
        % More directly: T_c_w_col = -R_cw_dannce * T_wc_col_dannce
        Location_cam_center_in_world_col = -R_cw_dannce * T_wc_col_dannce;
        Location_for_plot_row = Location_cam_center_in_world_col'; % Ensure 1x3 row for plotCamera

        all_calculated_Tcw_for_axis_limits(:, i) = Location_cam_center_in_world_col;
        
        plotCamera('Location', Location_for_plot_row, 'Orientation', Orientation_for_plot, 'Size', camSize, 'Color', base_colors(i,:), 'Opacity', 0.6);
        text(Location_for_plot_row(1), Location_for_plot_row(2), Location_for_plot_row(3) + camSize*0.8, strrep(currentCamName,'_',' '), 'Color', base_colors(i,:)*0.7, 'FontSize', 8, 'HorizontalAlignment','center');
    end
    
    % Set common axis limits based on calculated T_c_w values
    view(3);
    if any(~isnan(all_calculated_Tcw_for_axis_limits(:)))
        valid_t = all_calculated_Tcw_for_axis_limits(:, ~all(isnan(all_calculated_Tcw_for_axis_limits),1));
        if ~isempty(valid_t)
            min_c = min(valid_t,[],2); max_c = max(valid_t,[],2); center_c = (min_c+max_c)/2;
            range_c = max_c-min_c; range_c(range_c < 1e-5) = camSize*2; % Avoid zero range
            max_r = max(range_c); if max_r < 1e-5, max_r = camSize*4; end % Ensure some range
            margin = max(max_r*0.6, camSize*2.5);
            xlim([center_c(1)-margin,center_c(1)+margin]); 
            ylim([center_c(2)-margin,center_c(2)+margin]); 
            zlim([center_c(3)-margin,center_c(3)+margin]);
        else
            warning('No valid calculated T_c_w camera positions for axis limits. Using fallback.');
            xlim([-100 100]);ylim([-100 100]);zlim([-100 100]); % Fallback limits
        end
    else
        warning('All calculated T_c_w camera positions are NaN. Using fallback limits.');
        xlim([-100 100]);ylim([-100 100]);zlim([-100 100]); % Fallback limits
    end
    hold off;
    disp('DEMO_MODE (Label3D.m interpretation) plotting complete.');

else
    % --- Individual Cam_*_params.mat Mode (Logic revised for R_c_w, T_w_c_row input) ---
    title('Multi-Camera Setup (Individual Files - Format: r=Rcw, t=Twc_row)');
    matDir = "A:/EnclosureProjects/inprep/freemat/data/experiments/good/240528/video/calibration/fixed_timestamp/multical/label3d"; % Path for individual .mat files

    files = dir(fullfile(matDir, 'Cam_*_params.mat'));

    if isempty(files)
        error('No camera parameter files found in: %s. Ensure DEMO_MODE is set correctly or path is valid.', matDir);
    end
    
    fprintf('Found %d camera files from %s. Plotting...', length(files),matDir);
    all_t = zeros(3, length(files)); 
    colors = jet(length(files));

    for i = 1:length(files)
        camFile = fullfile(matDir, files(i).name);
        fprintf('Loading %s...', files(i).name);
        
        try
            camData = load(camFile);
            
            if ~isfield(camData, 't') || ~isfield(camData, 'r')
                warning('File %s does not contain ''t'' and ''r''. Skipping.', files(i).name);
                all_t(:, i) = NaN;
                continue;
            end
            
            % Load data assuming format: 
            % camData.r is R_c_w (camera-to-world rotation)
            % camData.t is T_w_c_row (world origin in camera coords, 1x3 row vector, mm)
            R_cam_to_world = camData.r;
            T_world_in_cam_row = camData.t; 
            
            % Ensure T_world_in_cam_row is 1x3
            if ~isequal(size(T_world_in_cam_row), [1,3])
                if isequal(size(T_world_in_cam_row), [3,1])
                    T_world_in_cam_row = T_world_in_cam_row'; % Transpose if it was 3x1
                    warning('Cam %s .t was 3x1, transposed to 1x3 for T_w_c_row convention.', files(i).name);
                else
                    warning('Loaded .t for Cam %s is not 1x3 or 3x1. Skipping.', files(i).name);
                    all_t(:, i) = NaN;
                    continue;
                end
            end

            % plotCamera expects:
            %   Orientation = R_w_c
            %   Location    = T_c_w (camera center in world, 1x3 row vector)
            Orientation_for_plotCamera = R_cam_to_world'; % R_w_c = R_c_w'
            
            % Calculate T_c_w_row = -T_w_c_row * R_w_c'
            % R_w_c' is R_cam_to_world' = (camData.r)' 
            Location_for_plot_row = -T_world_in_cam_row * R_cam_to_world'; % Corrected: multiply by R_c_w transpose (R_w_c)
            
            % Store the calculated T_c_w (as column vector) for axis limits
            all_t(:, i) = Location_for_plot_row'; 
            
            plotCamera('Location', Location_for_plot_row, 'Orientation', Orientation_for_plotCamera, 'Size', camSize, 'Color', colors(i,:), 'Opacity', 0.5); 
            
            labelOffset = camSize * 0.6;
            text(Location_for_plot_row(1), Location_for_plot_row(2), Location_for_plot_row(3) + labelOffset, ...
                 sprintf('Cam_%03d', str2double(files(i).name(5:7))), ...
                 'Color', colors(i,:), ...
                 'FontWeight', 'bold', ...
                 'HorizontalAlignment', 'center', ...
                 'FontSize', 8);
                 
        catch ME
            warning('Error processing file %s: %s. Skipping.', files(i).name, ME.message);
            all_t(:, i) = NaN;
        end
    end
end

% --- Dynamic Axis Limits (common to both modes) ---
view(3); % Standard 3D view

if ~isempty(all_t) && size(all_t, 2) > 0
    valid_t_cols = ~all(isnan(all_t), 1); 
    if any(valid_t_cols)
        valid_t = all_t(:, valid_t_cols); 

        min_coords = min(valid_t, [], 2);
        max_coords = max(valid_t, [], 2);
        center = (min_coords + max_coords) / 2;
        range_coords = max_coords - min_coords;
        
        % Ensure range isn't zero for single camera or all cameras at same point
        range_coords(range_coords < 1e-6) = camSize * 2; % Use a multiple of camSize as min range
        
        max_dim_range = max(range_coords);
        if max_dim_range < 1e-6, max_dim_range = camSize * 4; end % If all points are identical or very close
        
        % Set margin based on the range and camera size
        margin = max(max_dim_range * 0.5, camSize * 2); % Adjusted margin factor
        
        xlim([center(1) - margin, center(1) + margin]);
        ylim([center(2) - margin, center(2) + margin]);
        zlim([center(3) - margin, center(3) + margin]);
    else
        warning('No valid camera positions to set axis limits. Using default limits.');
        xlim([-1000 1000]); ylim([-1000 1000]); zlim([-1000 1000]); % Default fallback
    end
else
    warning('No camera positions available to set axis limits. Using default limits.');
    xlim([-1000 1000]); ylim([-1000 1000]); zlim([-1000 1000]); % Default fallback
end

hold off;
disp('Plotting complete.');
