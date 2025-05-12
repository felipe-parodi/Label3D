# Label3D

A highly tailored version of Diego Aldarondo's [implementation](https://github.com/diegoaldarondo/Label3D).

Includes:
- Plotting of camera principal point.
- Ability to swap animal IDs per view.
- 2D data loading from .mat file.
- No reprojection of labeled points.
- Pagination of camera views.
- Smaller marker, skeleton-link sizes.
- TODO: visibility toggle

Current flow:
1. Load 2D pose data, frames, and camera calibration parameters.
2. Correct IDs and poses as needed.
3. Triangulate 3D poses.
4. Review.
5. Save.

## Original Features
1. Simultaneous viewing of any number of camera views
2. Multiview triangulation of 3D keypoints
3. Point-and-click and draggable gestures to label keypoints
4. Zooming, panning, and other default Matlab gestures
5. Integration with `Animator` classes

## Usage
Requires >= `Matlab 2019b`

Label3D takes a cell arrays of structs of camera parameters as in
https://github.com/spoonsso/DANNCE, a cell array of corresponding videos (h,w,c,N),
and a skeleton struct defining a directed graph. Please look at `example.m`
for examples on how to format data.

```
labelGui = Label3D(params, videos, skeleton);
```

## [Manual](https://github.com/diegoaldarondo/Label3D/wiki)
* [About](https://github.com/diegoaldarondo/Label3D/wiki/About)
* [Documentation](https://github.com/diegoaldarondo/Label3D/wiki/Documentation)
* [Gestures and hotkeys](https://github.com/diegoaldarondo/Label3D/wiki/Gestures-and-hotkeys)
* [Setup](https://github.com/diegoaldarondo/Label3D/wiki/Setup)

Original implementation by Diego Aldarondo (2019)

Some code adapted from https://github.com/talmo/leap
