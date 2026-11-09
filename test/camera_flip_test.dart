import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:chess3d/scene/orbit_camera.dart';
import 'package:chess3d/scene/math3.dart';

void main() {
  test('flip preserves camera tilt, distance, and target', () {
    final camera = OrbitCamera()..animations = false;
    camera.setSpherical(16, 0.72, 0.4, const V3(1, 0.5, 2));
    final originalTarget = camera.target;
    camera.flip();
    expect(camera.radius, closeTo(16, 1e-8));
    expect(camera.phi, closeTo(0.72, 1e-8));
    expect(camera.target.x, closeTo(originalTarget.x, 1e-8));
    expect(camera.target.y, closeTo(originalTarget.y, 1e-8));
    expect(camera.target.z, closeTo(originalTarget.z, 1e-8));
    expect(math.cos(camera.theta - 0.4), closeTo(-1, 1e-8));
  });

  test('normal camera reset is higher than the former 52 degree view', () {
    final camera = OrbitCamera()..animations = false;
    camera.reset();
    expect(camera.phi, lessThan(52 * math.pi / 180));
    expect(camera.phi, greaterThan(0.4));
  });

  test('board coordinate anchors project differently after orbit', () {
    final camera = OrbitCamera()..animations = false;
    camera.setViewport(600, 900);
    final a = camera.project(const V3(-4.2, 0.464, 4.2), 600, 900);
    expect(a, isNotNull);
    camera.flip();
    final b = camera.project(const V3(-4.2, 0.464, 4.2), 600, 900);
    expect(b, isNotNull);
    expect((a!.x - b!.x).abs(), greaterThan(1));
  });

  group('default view fits the whole board on every screen shape', () {
    const sizes = [
      (360.0, 780.0), (412.0, 915.0), (600.0, 1000.0), (800.0, 1280.0),
      (1280.0, 800.0), (1000.0, 700.0), (2000.0, 900.0), (500.0, 500.0),
    ];
    for (final (w, h) in sizes) {
      for (final white in [true, false]) {
        test('${w.toInt()}x${h.toInt()} from ${white ? 'White' : 'Black'}', () {
          final c = OrbitCamera()..animations = false;
          c.setViewport(w, h);
          c.reset(animate: false, whiteSide: white);
          for (final x in [-4.75, 4.75]) {
            for (final y in [0.0, 0.5]) {
              for (final z in [-4.75, 4.75]) {
                final p = c.project(V3(x, y, z), w, h);
                expect(p, isNotNull);
                expect(p!.x, inInclusiveRange(0, w), reason: 'corner ($x,$y,$z) x=${p.x}');
                expect(p.y, inInclusiveRange(0, h), reason: 'corner ($x,$y,$z) y=${p.y}');
              }
            }
          }
        });
      }
    }

    test('flip keeps the board in view after a pinch-zoom and pan', () {
      final c = OrbitCamera()..animations = false;
      c.setViewport(600, 1000);
      c.reset(animate: false);
      c.setSpherical(c.radius * 0.9, 0.6, 0.3, const V3(0.4, 0.4, -0.3));
      final before = (c.radius, c.phi, c.target);
      c.flip();
      expect(c.radius, closeTo(before.$1, 1e-9));
      expect(c.phi, closeTo(before.$2, 1e-9));
      expect(c.target.x, closeTo(before.$3.x, 1e-9));
      expect(c.target.z, closeTo(before.$3.z, 1e-9));
      expect(math.cos(c.theta - 0.3), closeTo(-1, 1e-9));
    });
  });
}
