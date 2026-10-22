import 'dart:ui';

import 'package:meta/meta.dart';

/// How a preview frame relates to what is on screen.
///
/// A camera writes frames in its sensor's orientation, so the image has to be
/// turned before it is shown. That turn moves the coordinate system too: the
/// regions of interest in `PreviewConfig` are normalised against the frame,
/// while the overlay the clinician drags is normalised against the screen. Two
/// different frames of reference, one of which the user can see.
///
/// Keeping the conversion here, as arithmetic on rectangles, is what makes it
/// testable without a camera.
@immutable
final class PreviewGeometry {
  const PreviewGeometry({
    required this.frameWidth,
    required this.frameHeight,
    required this.rotationDegrees,
  }) : assert(
          rotationDegrees == 0 ||
              rotationDegrees == 90 ||
              rotationDegrees == 180 ||
              rotationDegrees == 270,
          'a camera reports its orientation in quarter turns',
        );

  /// The frame as the camera writes it, before any rotation.
  final int frameWidth;
  final int frameHeight;

  /// Clockwise degrees the frame is turned by to be displayed upright.
  final int rotationDegrees;

  /// Quarter turns for a `RotatedBox`, which also turns clockwise.
  int get quarterTurns => rotationDegrees ~/ 90;

  /// True when the turn swaps width and height.
  bool get swapsAxes => rotationDegrees == 90 || rotationDegrees == 270;

  /// Width over height of the image as displayed.
  double get displayAspectRatio =>
      swapsAxes ? frameHeight / frameWidth : frameWidth / frameHeight;

  /// Maps a rectangle the user positioned on screen onto the frame the camera
  /// writes, both in normalised coordinates.
  ///
  /// Derived from where the corners go. Turning an image a quarter turn
  /// clockwise sends its top-left corner to the top-right, so a frame point
  /// `(u, v)` appears at `(1 - v, u)`; inverting that gives `u = y` and
  /// `v = 1 - x`, which is the first case below.
  Rect toFrame(Rect display) => switch (rotationDegrees) {
        90 => Rect.fromLTRB(
            display.top,
            1 - display.right,
            display.bottom,
            1 - display.left,
          ),
        180 => Rect.fromLTRB(
            1 - display.right,
            1 - display.bottom,
            1 - display.left,
            1 - display.top,
          ),
        270 => Rect.fromLTRB(
            1 - display.bottom,
            display.left,
            1 - display.top,
            display.right,
          ),
        _ => display,
      };

  /// The inverse of [toFrame], for drawing something the camera reported.
  Rect toDisplay(Rect frame) => switch (rotationDegrees) {
        90 => Rect.fromLTRB(
            1 - frame.bottom,
            frame.left,
            1 - frame.top,
            frame.right,
          ),
        180 => Rect.fromLTRB(
            1 - frame.right,
            1 - frame.bottom,
            1 - frame.left,
            1 - frame.top,
          ),
        270 => Rect.fromLTRB(
            frame.top,
            1 - frame.right,
            frame.bottom,
            1 - frame.left,
          ),
        _ => frame,
      };
}
