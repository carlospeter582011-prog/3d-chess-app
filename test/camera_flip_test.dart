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
}
