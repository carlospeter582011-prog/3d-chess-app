// Orbit camera: a port of three.js OrbitControls (as configured by the web version) plus the fly-to animation.
//
// One finger rotates, two fingers pinch-zoom and pan along the table, with damping.
// The camera orbits `target` using spherical coordinates (radius, phi from +Y, theta around Y from +Z toward +X),
// exactly like three.js, so the board is seen from White's side (+Z) at theta = 0.

import 'dart:math' as math;

import 'math3.dart';

class _Fly {
  double t = 0;
  final double dur;
  final double r0, p0, th0, r1, p1, th1;
  final V3 target;
  _Fly(this.dur, this.r0, this.p0, this.th0, this.r1, this.p1, this.th1, this.target);
}

class OrbitCamera {
  static const double minDistance = 5;
  static const double maxDistance = 32; // far enough to see the whole table, never loses the board
  static const double minPolar = 0.02;
  static final double maxPolar = math.pi * 0.49; // never go below the table
  static const double damping = 0.09;
  static const double rotateSpeed = 0.7;
  static const double zoomSpeed = 0.9;
  static const double panSpeed = 0.8;
  static const double autoRotateSpeed = 0.7;
  static const double flyMillis = 700;

  double radius = 14;
  double phi = degToRad(52);
  double theta = 0;
  V3 target = const V3(0, 0.4, 0);

  /// Vertical field of view in degrees (wider on portrait phones so the board stays big).
  double fov = 38;
  double aspect = 1;

  /// Height of the view in logical pixels, used to scale touch gestures.
  double viewHeight = 600;

  bool autoRotate = false;

  /// When false camera moves apply instantly (used by tests).
  bool animations = true;

  double _dTheta = 0, _dPhi = 0, _scale = 1;
  V3 _pan = V3.zero;
  _Fly? _fly;

  bool get flying => _fly != null;

  // ------------------------------------------------------------------ derived
  V3 get offset => V3(
        radius * math.sin(phi) * math.sin(theta),
        radius * math.cos(phi),
        radius * math.sin(phi) * math.cos(theta),
      );

  V3 get eye => target + offset;

  /// Camera basis: forward, right, up.
  ({V3 forward, V3 right, V3 up}) get basis {
    final f = (target - eye).normalized;
    final r = f.cross(V3.up).normalized;
    final u = r.cross(f);
    return (forward: f, right: r, up: u);
  }

  /// 'w' when looking from White's side of the board (+Z), 'b' from Black's side.
  bool get fromWhiteSide => math.cos(theta) >= 0;

  /// Default tilt (from vertical) of the reset view: a little higher than the old 52 degrees so pawns hide less.
  static final double defaultPhi = degToRad(43);

  /// Points that must stay on screen: the wooden frame (outer half-size ~4.75, y 0..0.5) and the tops of the tallest
  /// pieces on the four corner squares.
  static const List<V3> _fitPoints = [
    V3(-4.75, 0, -4.75), V3(4.75, 0, -4.75), V3(-4.75, 0, 4.75), V3(4.75, 0, 4.75),
    V3(-4.75, 0.5, -4.75), V3(4.75, 0.5, -4.75), V3(-4.75, 0.5, 4.75), V3(4.75, 0.5, 4.75),
    V3(-3.5, 2.0, -3.5), V3(3.5, 2.0, -3.5), V3(-3.5, 2.0, 3.5), V3(3.5, 2.0, 3.5),
  ];

  /// Fraction of the half-width / half-height of the view the board may use (the rest is margin for the HUD).
  static const double fitX = 0.94, fitY = 0.80;

  /// Smallest camera distance at which every fit point projects inside the view, for the current field of view and
  /// aspect ratio, seen from tilt [phi] around [tgt]. Works for any screen shape because it uses the real projection
  /// (the near edge of the board is wider on screen than the far one) instead of a flat width estimate. The result is
  /// the same from both sides of the board.
  double fitDistance({double? phi, V3 tgt = const V3(0, 0.4, 0)}) {
    final p = phi ?? defaultPhi;
    final th = math.tan(degToRad(fov) / 2);
    bool fits(double r) {
      final off = V3(0, r * math.cos(p), r * math.sin(p));
      final f = (off * -1.0).normalized;
      final right = f.cross(V3.up).normalized;
      final up = right.cross(f);
      for (final q in _fitPoints) {
        final v = q - (tgt + off);
        final z = v.dot(f);
        if (z <= 0.01) return false;
        if (v.dot(right).abs() / (z * th * aspect) > fitX) return false;
        if (v.dot(up).abs() / (z * th) > fitY) return false;
      }
      return true;
    }

    var lo = 3.0, hi = 80.0;
    for (var i = 0; i < 48; i++) {
      final mid = (lo + hi) / 2;
      if (fits(mid)) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return hi;
  }

  /// Sets the viewport shape. Keeps the whole board visible after a rotation / resize.
  void setViewport(double width, double height, {bool boardReady = true}) {
    final w = math.max(1.0, width), h = math.max(1.0, height);
    final prevAspect = aspect;
    aspect = w / h;
    viewHeight = h;
    fov = aspect < 0.85 ? 50 : 38;
    if ((prevAspect - aspect).abs() > 0.01 && boardReady) {
      final want = fitDistance();
      if (radius < want) radius = want;
    }
  }

  // ------------------------------------------------------------------ gestures
  /// One-finger drag by (dx, dy) logical pixels.
  void rotateByPixels(double dx, double dy) {
    final h = math.max(1.0, viewHeight);
    _dTheta -= 2 * math.pi * dx / h * rotateSpeed;
    _dPhi -= 2 * math.pi * dy / h * rotateSpeed;
    _fly = null;
  }

  /// Pinch: [ratio] is the new finger distance divided by the previous one (>1 zooms in).
  void zoomByRatio(double ratio) {
    if (ratio <= 0 || ratio.isNaN || ratio.isInfinite) return;
    _scale /= math.pow(ratio, zoomSpeed);
    _fly = null;
  }

  /// Finger lifted while still moving at ([vx], [vy]) logical px/s: the view keeps gliding for a moment (inertia)
  /// instead of stopping dead. The extra rotation is spread over the damping, about half a second.
  void fling(double vx, double vy) {
    const glide = 0.2; // seconds of the release velocity that carry on
    final h = math.max(1.0, viewHeight);
    final cap = 0.55 * h;
    final dx = clampD(vx * glide, -cap, cap), dy = clampD(vy * glide, -cap, cap);
    _dTheta -= 2 * math.pi * dx / h * rotateSpeed;
    _dPhi -= 2 * math.pi * dy / h * rotateSpeed;
  }

  /// Two-finger drag by (dx, dy) logical pixels: slides the view over the table.
  void panByPixels(double dx, double dy) {
    final h = math.max(1.0, viewHeight);
    final targetDistance = offset.length * math.tan(degToRad(fov / 2)) * 2;
    final right = basis.right;
    final dist = 2 * (dx * panSpeed) * targetDistance / h;
    _pan = _pan + right * (-dist);
    final fwd = V3.up.cross(right);
    final distUp = 2 * (dy * panSpeed) * targetDistance / h;
    _pan = _pan + fwd * distUp;
    _fly = null;
  }

  // ------------------------------------------------------------------ animation
  void setSpherical(double r, double p, double th, V3 tgt) {
    radius = r;
    phi = p;
    theta = th;
    target = tgt;
    _dTheta = _dPhi = 0;
    _scale = 1;
    _pan = V3.zero;
    _fly = null;
  }

  /// Moves the camera to a spherical position around [tgt], by the shortest way round.
  void flyTo(double r, double p, double th, V3 tgt, {bool animate = true}) {
    var dTheta = th - theta;
    dTheta = math.atan2(math.sin(dTheta), math.cos(dTheta));
    final toTheta = theta + dTheta;
    if (!animate || !animations) {
      setSpherical(r, p, toTheta, tgt);
      return;
    }
    _dTheta = _dPhi = 0;
    _scale = 1;
    _pan = V3.zero;
    _fly = _Fly(flyMillis, radius, phi, theta, r, p, toTheta, tgt);
  }

  /// side: true = look from White's side (+Z), false = Black's side (-Z).
  void reset({bool animate = true, bool whiteSide = true, bool top = false}) {
    flyTo(fitDistance(phi: top ? 0.02 : defaultPhi), top ? 0.02 : defaultPhi, whiteSide ? 0 : math.pi, const V3(0, 0.4, 0), animate: animate);
  }

  /// Flips the view to the other side of the board.
  void flip() {
    flyTo(radius, phi, theta + math.pi, target);
  }

  /// Advances damping / animation by [dt] seconds. Returns true when the view changed.
  bool update(double dt) {
    final beforeEye = eye, beforeTarget = target, beforeFov = fov;
    final double k = 1 - math.pow(1 - damping, math.max(0.0, dt) * 60).toDouble();

    final fly = _fly;
    if (fly != null) {
      fly.t += dt * 1000;
      final e = easeInOut(math.min(1.0, fly.t / fly.dur));
      radius = fly.r0 + (fly.r1 - fly.r0) * e;
      phi = fly.p0 + (fly.p1 - fly.p0) * e;
      theta = fly.th0 + (fly.th1 - fly.th0) * e;
      target = target.lerp(fly.target, 0.2 + 0.8 * e);
      if (fly.t >= fly.dur) _fly = null;
    } else {
      if (autoRotate) _dTheta -= 2 * math.pi / 60 * autoRotateSpeed * dt;
      theta += _dTheta * k;
      phi += _dPhi * k;
      phi = clampD(phi, minPolar, maxPolar);
      // zoom glides too: only a fraction of the requested zoom is applied each frame
      radius = clampD(radius * math.pow(_scale, k), minDistance, maxDistance);
      _scale = math.pow(_scale, 1 - k).toDouble();
      if ((_scale - 1).abs() < 1e-4) _scale = 1;
      if (radius <= minDistance + 1e-9 && _scale < 1 || radius >= maxDistance - 1e-9 && _scale > 1) _scale = 1;
      target = target + _pan * k;
      _dTheta *= (1 - k);
      _dPhi *= (1 - k);
      _pan = _pan * (1 - k);
    }
    _clampTarget();

    const eps = 1e-7;
    return (eye - beforeEye).length > eps || (target - beforeTarget).length > eps || fov != beforeFov;
  }

  void _clampTarget() {
    target = V3(clampD(target.x, -4.5, 4.5), clampD(target.y, 0, 2.5), clampD(target.z, -4.5, 4.5));
  }

  // ------------------------------------------------------------------ projection / picking
  /// Ray from the camera through a point of the view given in logical pixels (origin top-left).
  ({V3 origin, V3 dir}) rayThrough(double sx, double sy, double viewWidth, double viewHeightPx) {
    final nx = (sx / viewWidth) * 2 - 1;
    final ny = -((sy / viewHeightPx) * 2 - 1);
    final b = basis;
    final th = math.tan(degToRad(fov) / 2);
    final dir = (b.forward + b.right * (nx * th * aspect) + b.up * (ny * th)).normalized;
    return (origin: eye, dir: dir);
  }

  /// Screen position (logical px) of a world point, or null when it is behind the camera.
  ({double x, double y})? project(V3 p, double viewWidth, double viewHeightPx) {
    final b = basis;
    final v = p - eye;
    final z = v.dot(b.forward);
    if (z <= 1e-6) return null;
    final th = math.tan(degToRad(fov) / 2);
    final nx = v.dot(b.right) / (z * th * aspect);
    final ny = v.dot(b.up) / (z * th);
    return (x: (nx + 1) / 2 * viewWidth, y: (1 - ny) / 2 * viewHeightPx);
  }
}
