// Spline-based cinematic camera. A shot is a list of keyframes; between keyframes the camera follows a cubic
// Hermite spline (non-uniform Catmull-Rom tangents) so speed changes smoothly. Everything is a pure function of the
// frame number. The camera is expressed as an orbit around a target (distance, azimuth, elevation) because that keeps
// every shot framed on its subject and makes aspect-ratio adaptation a matter of scaling the distance.
import { PieceState } from './timeline';

export interface Key {
  f: number;
  /** distance from target */
  r: number;
  /** azimuth in degrees, 0 = looking from White's side (+z) */
  th: number;
  /** angle from straight down in degrees (90 = horizon) */
  ph: number;
  /** static target */
  t: [number, number, number];
  fov: number;
  /** 0..1 blend towards the followed piece (see Shot.follow) */
  w: number;
  /** extra target height when following */
  oy: number;
}

export const K = (f: number, r: number, th: number, ph: number, t: [number, number, number], fov = 32, w = 0, oy = 0.5): Key => ({ f, r, th, ph, t, fov, w, oy });

export interface Shot {
  from: number;
  to: number;
  keys: Key[];
  /** piece id to track (used where a key has w > 0) */
  follow?: number;
  /** second piece: the target blends to the midpoint of both (framing a duel) */
  follow2?: number;
  /** multiplier on the distance in portrait frames (tall, narrow) */
  pr: number;
  /** multiplier on the distance in landscape frames */
  lr?: number;
  /** extra vertical shift of the target in portrait frames, to place the subject above the lower safe area */
  pdy?: number;
  /** multiplier on the field of view in portrait frames (wider lens for top-down shots) */
  pf?: number;
}

export interface Cam {
  pos: [number, number, number];
  look: [number, number, number];
  fov: number;
}

const vec = (k: Key) => [k.r, k.th, k.ph, k.t[0], k.t[1], k.t[2], k.fov, k.w, k.oy];

function hermite(keys: Key[], f: number): number[] {
  if (f <= keys[0].f) return vec(keys[0]);
  if (f >= keys[keys.length - 1].f) return vec(keys[keys.length - 1]);
  let i = 0;
  while (f > keys[i + 1].f) i++;
  const k0 = keys[i], k1 = keys[i + 1];
  const dt = k1.f - k0.f;
  const u = (f - k0.f) / dt;
  const p0 = vec(k0), p1 = vec(k1);
  const tangent = (j: number) => {
    // time-aware finite difference; one-sided at the ends so shots do not start or stop dead
    const a = keys[Math.max(0, j - 1)], b = keys[Math.min(keys.length - 1, j + 1)];
    const va = vec(a), vb = vec(b);
    const span = b.f - a.f || 1;
    return va.map((_, c) => (vb[c] - va[c]) / span);
  };
  const m0 = tangent(i), m1 = tangent(i + 1);
  const u2 = u * u, u3 = u2 * u;
  const h00 = 2 * u3 - 3 * u2 + 1, h10 = u3 - 2 * u2 + u, h01 = -2 * u3 + 3 * u2, h11 = u3 - u2;
  return p0.map((_, c) => h00 * p0[c] + h10 * dt * m0[c] + h01 * p1[c] + h11 * dt * m1[c]);
}

export function cameraAt(shots: Shot[], frame: number, portrait: boolean, pieces: PieceState[]): Cam {
  const shot = shots.find((s) => frame >= s.from && frame < s.to) ?? shots[shots.length - 1];
  const [r, th, ph, tx, ty, tz, fov, w, oy] = hermite(shot.keys, Math.min(frame, shot.to - 1));
  let t: [number, number, number] = [tx, ty, tz];
  const a = shot.follow !== undefined ? pieces.find((p) => p.id === shot.follow) : undefined;
  if (a) {
    let fx = a.x, fz = a.z, fy = a.y;
    const b = shot.follow2 !== undefined ? pieces.find((p) => p.id === shot.follow2) : undefined;
    if (b) { fx = (a.x + b.x) / 2; fz = (a.z + b.z) / 2; fy = (a.y + b.y) / 2; }
    const ww = Math.min(1, Math.max(0, w));
    t = [tx + (fx - tx) * ww, ty + (fy + oy - ty) * ww, tz + (fz - tz) * ww];
  }
  const rr = r * (portrait ? shot.pr : shot.lr ?? 1);
  if (portrait && shot.pdy) t = [t[0], t[1] + shot.pdy, t[2]];
  const thr = (th * Math.PI) / 180, phr = (ph * Math.PI) / 180;
  const pos: [number, number, number] = [t[0] + rr * Math.sin(phr) * Math.sin(thr), t[1] + rr * Math.cos(phr), t[2] + rr * Math.sin(phr) * Math.cos(thr)];
  return { pos, look: t, fov: fov * (portrait ? shot.pf ?? 1 : 1) };
}

