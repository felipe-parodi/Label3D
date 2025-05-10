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

    %uniqueColors = customColorMap(nAnimals);
    %markerColors = repelem(uniqueColors, nMarkers , 1);
    %newSkeleton.marker_colors = markerColors;
end

