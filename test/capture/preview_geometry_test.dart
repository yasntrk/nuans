import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuans/features/capture/application/preview_geometry.dart';

void main() {
  PreviewGeometry at(int degrees) => PreviewGeometry(
        frameWidth: 1920,
        frameHeight: 1080,
        rotationDegrees: degrees,
      );

  test('a quarter turn swaps the displayed aspect ratio', () {
    expect(at(0).displayAspectRatio, closeTo(1920 / 1080, 1e-12));
    expect(at(90).displayAspectRatio, closeTo(1080 / 1920, 1e-12));
    expect(at(180).displayAspectRatio, closeTo(1920 / 1080, 1e-12));
    expect(at(270).displayAspectRatio, closeTo(1080 / 1920, 1e-12));
  });

  test('without rotation the two frames of reference coincide', () {
    const rect = Rect.fromLTWH(0.2, 0.3, 0.4, 0.5);
    expect(at(0).toFrame(rect), rect);
    expect(at(0).toDisplay(rect), rect);
  });

  test('a quarter turn clockwise sends the top-left corner to the top-right',
      () {
    // A small square in the frame's top-left corner.
    const corner = Rect.fromLTWH(0, 0, 0.1, 0.1);
    final displayed = at(90).toDisplay(corner);
    expect(displayed.right, closeTo(1.0, 1e-12));
    expect(displayed.top, closeTo(0.0, 1e-12));
    expect(displayed.width, closeTo(0.1, 1e-12));
  });

  test('toFrame and toDisplay invert each other at every rotation', () {
    const rect = Rect.fromLTWH(0.17, 0.29, 0.33, 0.41);
    for (final degrees in [0, 90, 180, 270]) {
      final geometry = at(degrees);
      final roundTrip = geometry.toDisplay(geometry.toFrame(rect));
      expect(roundTrip.left, closeTo(rect.left, 1e-12), reason: '$degrees');
      expect(roundTrip.top, closeTo(rect.top, 1e-12), reason: '$degrees');
      expect(roundTrip.width, closeTo(rect.width, 1e-12), reason: '$degrees');
      expect(roundTrip.height, closeTo(rect.height, 1e-12), reason: '$degrees');
    }
  });

  test('a rotated rectangle stays inside the unit square', () {
    const rect = Rect.fromLTWH(0.34, 0.26, 0.32, 0.48);
    for (final degrees in [0, 90, 180, 270]) {
      final mapped = at(degrees).toFrame(rect);
      expect(mapped.left, greaterThanOrEqualTo(-1e-12), reason: '$degrees');
      expect(mapped.top, greaterThanOrEqualTo(-1e-12), reason: '$degrees');
      expect(mapped.right, lessThanOrEqualTo(1 + 1e-12), reason: '$degrees');
      expect(mapped.bottom, lessThanOrEqualTo(1 + 1e-12), reason: '$degrees');
    }
  });

  test('a quarter turn turns a tall rectangle into a wide one', () {
    // The default tooth box is taller than it is wide on screen; in the
    // landscape frame the camera writes, it has to be wider than it is tall.
    const tooth = Rect.fromLTWH(0.34, 0.26, 0.32, 0.48);
    final inFrame = at(90).toFrame(tooth);
    expect(inFrame.width, closeTo(tooth.height, 1e-12));
    expect(inFrame.height, closeTo(tooth.width, 1e-12));
  });

  test('a rotation that is not a quarter turn is rejected', () {
    expect(
      () => PreviewGeometry(
        frameWidth: 1920,
        frameHeight: 1080,
        rotationDegrees: 45,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
