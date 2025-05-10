# Label3D

Modified Label3D to include:
- Plotting of principal point
- Ability to swap animal IDs in view
- 2D data loading from .mat file
- No reprojection of labeled points
- TODO: visibility toggle

is a GUI for the manual labeling of 3D keypoints in multiple cameras.
![Label3D Animation](common/label3dAnimation.gif)

## Installation

See Diego Aldarondo's [implementation](https://github.com/diegoaldarondo/Label3D) for full installation instructions.

## Original Features
1. Simultaneous viewing of any number of camera views
2. Multiview triangulation of 3D keypoints
3. Point-and-click and draggable gestures to label keypoints
4. Zooming, panning, and other default Matlab gestures
5. Integration with `Animator` classes

## Usage
Requires `Matlab 2019b`, `Matlab 2020a`, or `Matlab 2020b`

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
