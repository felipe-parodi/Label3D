function newSkeleton = multiAnimalSkeleton(baseSkeleton, nAnimals)
    % duplicate an animal skeleton n times e.g. for multi-animal labeling
    % Also assigns a unique marker color to each skeleton (skeleton.marker_color)

    % E.g. usage: 
    % rat23 = load('skeletons/rat23')
    % rat23_2 = multiAnimalSkeleton(rat23, 2)
    % pass rat23_2 as skeleton parameter when starting label3d

    % Copy the baseSkeleton struct so we do not modify the original
    newSkeleton = baseSkeleton;

    nMarkers = length(baseSkeleton.joint_names);
    nConnections = size(baseSkeleton.joints_idx, 1);
    
    jointNamesPrefix = repmat(baseSkeleton.joint_names, 1, nAnimals);
    jointNamesPostfix = num2cell(repelem((1:nAnimals)', nMarkers, 1))';
    jointNamesCombined = cellfun(@(x,y) strcat( x, '_', num2str(y) ) , ...
        jointNamesPrefix, jointNamesPostfix, 'UniformOutput', false);


    newSkeleton.joint_names = jointNamesCombined;

    adjMatrixBase = repmat(baseSkeleton.joints_idx, nAnimals, 1);
    adjMatrixModifier = (repelem(repmat((1:nAnimals)', 1, 2), ...
        nConnections, 1) - 1) * nMarkers;
    jointIndex = adjMatrixBase + cast(adjMatrixModifier, class(adjMatrixBase));

    newSkeleton.joints_idx = jointIndex;

    % Logic for distinct animal segment colors
    newSkeleton.color = []; % Initialize

    % Define base color themes for animals
    % Each row is an RGB triplet for an animal's segments
    animal_color_themes = [
        0.2, 0.4, 0.8;  % Bluish for Animal 1
        0.8, 0.3, 0.2;  % Reddish for Animal 2
        0.2, 0.8, 0.4;  % Greenish for Animal 3
        0.8, 0.8, 0.2;  % Yellowish for Animal 4
        0.6, 0.2, 0.8;  % Purplish for Animal 5
        0.8, 0.5, 0.2   % Orangish for Animal 6
    ];

    if nAnimals > size(animal_color_themes, 1)
        warning('multiAnimalSkeleton:NotEnoughColors', ...
                'Not enough predefined distinct color themes for all animals. Colors will be recycled.');
    end

    for i = 1:nAnimals
        % Select a color theme for the current animal
        % Cycle through themes if nAnimals > number of defined themes
        theme_idx = mod(i-1, size(animal_color_themes, 1)) + 1;
        current_theme_color = animal_color_themes(theme_idx, :);

        % Create a color matrix for all segments of the current animal using this theme
        % nConnections is the number of segments for a single base skeleton
        animal_segments_colors = repmat(current_theme_color, nConnections, 1);
        
        newSkeleton.color = [newSkeleton.color; animal_segments_colors];
    end

    % Ensure the number of color rows matches the total number of segment indices
    if size(newSkeleton.color, 1) ~= size(newSkeleton.joints_idx, 1)
        error('multiAnimalSkeleton:MismatchColorSegments', ...
              'Mismatch between the number of generated segment colors and segment indices.');
    end

    % --- START: Generate Per-Marker Colors ---
    base_joint_names = baseSkeleton.joint_names;
    nBaseMarkers = numel(base_joint_names);

    % Find indices for left, right, and center keypoints
    left_indices = find(contains(base_joint_names, 'left_'));
    right_indices = find(contains(base_joint_names, 'right_'));
    nose_index = find(strcmp(base_joint_names, 'nose'));
    % Basic validation
    if isempty(nose_index) || numel(left_indices) ~= 8 || numel(right_indices) ~= 8 || nBaseMarkers ~= 17
        warning('multiAnimalSkeleton:UnexpectedJoints', ...
                'Expected COCO-17 structure (1 nose, 8 left, 8 right) not found. Using default white markers.');
        base_marker_colors = repmat([1, 1, 1], nBaseMarkers, 1); % Default to white
    else
        % Define color gradients
        left_colors = [linspace(0.6, 0.0, 8)', linspace(0.8, 0.0, 8)', linspace(1.0, 0.8, 8)'];
        right_colors = [linspace(1.0, 0.8, 8)', linspace(0.6, 0.0, 8)', linspace(0.6, 0.0, 8)'];
        center_color = [1.0, 1.0, 0.0]; % Yellow for nose

        % Initialize base color array
        base_marker_colors = zeros(nBaseMarkers, 3);

        % Assign colors based on indices
        % We need to ensure the gradient follows the typical top-to-bottom order
        % COCO-17 order: nose, l_eye, r_eye, l_ear, r_ear, l_shoulder, r_shoulder, ... l_ankle, r_ankle
        % The find() indices might not be sorted anatomically, so we map carefully
        left_order_map = [2, 4, 6, 8, 10, 12, 14, 16]; % Indices in base_joint_names for left parts top->bottom
        right_order_map = [3, 5, 7, 9, 11, 13, 15, 17]; % Indices in base_joint_names for right parts top->bottom

        for i = 1:8
             base_marker_colors(left_order_map(i), :) = left_colors(i, :);
             base_marker_colors(right_order_map(i), :) = right_colors(i, :);
        end
        base_marker_colors(nose_index, :) = center_color;
    end

    % Replicate for nAnimals
    markerColors = repmat(base_marker_colors, nAnimals, 1);
    newSkeleton.marker_colors = markerColors;
    % --- END: Generate Per-Marker Colors ---

    %uniqueColors = customColorMap(nAnimals); % Original commented code
    %markerColors = repelem(uniqueColors, nMarkers , 1); % Original commented code
    %newSkeleton.marker_colors = markerColors; % Original commented code
end

