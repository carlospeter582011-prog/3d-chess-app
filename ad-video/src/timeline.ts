// Turns a list of chess plies into frame-accurate piece motion (deterministic: everything is a pure function of the
// frame number). Piece motion copies the app's own animation maths (arc, ease, capture shrink) and adds:
//  - an explicit per-ply schedule (start frame + duration) so camera, text and audio can be authored against it,
//  - arcs that clear any piece standing on the path (no pieces passing through each other),
//  - a slow "landing" ease for the decisive move,
//  - an elegant topple of the mated king (shudder -> tips over its base edge -> small bounce -> lies still).
import { Chess } from 'chess.js';

export const FPS = 30;
const ms = (v: number) => (v * FPS) / 1000;

export type PieceType = 'k' | 'q' | 'r' | 'b' | 'n' | 'p';
export type Color = 'w' | 'b';

export interface PieceState {
  id: number;
  type: PieceType;
  color: Color;
  x: number;
  y: number;
  z: number;
  rotY: number;
  rotZ: number;
  /** Optional orientation override as a quaternion [x, y, z, w] (used by the king's fall). */
  q?: [number, number, number, number];
  scale: number;
}

export const SURFACE_Y = 0.464;
/** Heights of the app's own piece models (from the GLB bounding boxes). */
export const PIECE_HEIGHT: Record<PieceType, number> = { k: 1.5, q: 1.3, b: 1.1, n: 1.0, r: 0.82, p: 0.74 };
export const KING_RADIUS = 0.31;
export const sqToWorld = (sq: string): [number, number] => [sq.charCodeAt(0) - 97 - 3.5, 3.5 - (sq.charCodeAt(1) - 49)];
const easeInOut = (k: number) => (k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2);
/** Decisive-move ease: leaves smoothly, then decelerates for a long, tense landing. */
const easeLand = (k: number) => 0.45 * easeInOut(k) + 0.55 * (1 - Math.pow(1 - k, 2.6));

export interface PlySpec {
  san: string;
  start: number;
  dur: number;
  slow?: boolean;
  final?: boolean;
}

export interface MoveEv {
  start: number;
  dur: number;
  id: number;
  type: PieceType;
  from: string;
  to: string;
  victimId?: number;
  slow: boolean;
  /** Peak height of the arc above the board surface. */
  arc: number;
  san: string;
}

export type SoundName = 'move' | 'capture' | 'impact' | 'fall1' | 'fall2';

export interface Scene {
  initial: { id: number; type: PieceType; color: Color; square: string }[];
  moves: MoveEv[];
  /** Frame the last move lands. */
  endMove: number;
  mate?: { kingId: number; attackerId: number; start: number; dir: [number, number] };
  sounds: { frame: number; name: SoundName }[];
  /** Frame the scene is fully finished (king lying still). */
  total: number;
}

export const SHUDDER_FRAMES = 15;
export const FALL_FRAMES = 28;
export const SETTLE_FRAMES = 14;

export function idOfSquare(scene: Scene, sq: string): number {
  return scene.initial.find((p) => p.square === sq)!.id;
}

export interface BuildOptions {
  fen?: string;
  /** Direction (x,z in world units) the mated king topples towards. Default: towards its own back rank. */
  fallDir?: [number, number];
  tail?: number;
}

export function buildFromPlies(plies: PlySpec[], opts: BuildOptions = {}): Scene {
  const chess = new Chess(opts.fen);
  const initial: Scene['initial'] = [];
  const idAt = new Map<string, number>();
  let nextId = 1;
  for (const row of chess.board())
    for (const sq of row) {
      if (!sq) continue;
      initial.push({ id: nextId, type: sq.type as PieceType, color: sq.color as Color, square: sq.square });
      idAt.set(sq.square, nextId++);
    }
  const typeOf = new Map(initial.map((p) => [p.id, p.type]));
  const moves: MoveEv[] = [];
  const sounds: Scene['sounds'] = [];
  let prevEnd = -Infinity;
  let end = 0;
  let lastAttacker = 0;
  for (const ply of plies) {
    const m = chess.move(ply.san);
    if (m.flags.includes('e') || m.flags.includes('k') || m.flags.includes('q') || m.promotion)
      throw new Error(`special move ${ply.san} is not supported by the ad timeline`);
    if (ply.start < prevEnd) throw new Error(`ply ${ply.san} starts before the previous ply has landed`);
    const id = idAt.get(m.from)!;
    const victimId = m.captured ? idAt.get(m.to) : undefined;
    const type = typeOf.get(id)!;
    // arc: knights hop; sliders lift just enough to clear whatever stands on the squares between
    let arc = type === 'n' ? 0.9 : 0.28;
    if (type !== 'n') {
      const dx = Math.sign(m.to.charCodeAt(0) - m.from.charCodeAt(0));
      const dy = Math.sign(m.to.charCodeAt(1) - m.from.charCodeAt(1));
      let f = m.from.charCodeAt(0) + dx, r = m.from.charCodeAt(1) + dy;
      let tallest = 0;
      while (f !== m.to.charCodeAt(0) || r !== m.to.charCodeAt(1)) {
        const b = idAt.get(String.fromCharCode(f) + String.fromCharCode(r));
        if (b) tallest = Math.max(tallest, PIECE_HEIGHT[typeOf.get(b)!]);
        f += dx;
        r += dy;
      }
      if (tallest > 0) arc = Math.max(arc, tallest + 0.22);
    }
    moves.push({ start: ply.start, dur: ply.dur, id, type, from: m.from, to: m.to, victimId, slow: !!ply.slow, arc, san: ply.san });
    // the knock is heard when the piece lands
    sounds.push({ frame: Math.round(ply.start + ply.dur * 0.9), name: m.captured ? 'capture' : 'move' });
    idAt.delete(m.from);
    idAt.set(m.to, id);
    prevEnd = end = ply.start + ply.dur;
    lastAttacker = id;
  }
  const scene: Scene = { initial, moves, endMove: end, sounds, total: end };
  const last = plies[plies.length - 1];
  if (last?.final) {
    if (!chess.isCheckmate()) throw new Error('the final ply is flagged final but is not checkmate');
    const loser = chess.turn();
    const kingId = initial.find((p) => p.type === 'k' && p.color === loser)!.id;
    // default: topple towards the loser's own back rank (away from the board centre along z)
    let dir: [number, number] = opts.fallDir ?? [0, loser === 'b' ? -1 : 1];
    const l = Math.hypot(dir[0], dir[1]);
    dir = [dir[0] / l, dir[1] / l];
    scene.mate = { kingId, attackerId: lastAttacker, start: end, dir };
    const fallStart = end + SHUDDER_FRAMES;
    sounds.push({ frame: end, name: 'impact' });
    sounds.push({ frame: fallStart + FALL_FRAMES, name: 'fall1' });
    sounds.push({ frame: fallStart + FALL_FRAMES + 7, name: 'fall2' });
    scene.total = fallStart + FALL_FRAMES + SETTLE_FRAMES;
  }
  scene.total = Math.ceil(scene.total + (opts.tail ?? 0));
  return scene;
}

/** Evenly paced plies for the phone demo (same pacing logic as the app's own animation). */
export function buildAuto(sans: string[], opts: { lead?: number; pauseMs?: number; fen?: string } = {}): Scene {
  const chess = new Chess(opts.fen);
  let t = opts.lead ?? 10;
  const plies: PlySpec[] = [];
  for (const san of sans) {
    const m = chess.move(san);
    const dist = Math.hypot(m.from.charCodeAt(0) - m.to.charCodeAt(0), m.from.charCodeAt(1) - m.to.charCodeAt(1));
    const dur = Math.round(ms(Math.min(700, 280 + dist * 70)));
    plies.push({ san, start: Math.round(t), dur });
    t += dur + ms(opts.pauseMs ?? 500);
  }
  return buildFromPlies(plies, { fen: opts.fen });
}

const rot = (v: [number, number, number], axis: [number, number, number], a: number): [number, number, number] => {
  // Rodrigues rotation of v about unit axis
  const [x, y, z] = axis, c = Math.cos(a), s = Math.sin(a);
  const dot = x * v[0] + y * v[1] + z * v[2];
  const cx = y * v[2] - z * v[1], cy = z * v[0] - x * v[2], cz = x * v[1] - y * v[0];
  return [v[0] * c + cx * s + x * dot * (1 - c), v[1] * c + cy * s + y * dot * (1 - c), v[2] * c + cz * s + z * dot * (1 - c)];
};

/** Piece positions at a film frame. */
export function stateAt(scene: Scene, frame: number): PieceState[] {
  const sq = new Map<number, string>();
  const gone = new Set<number>();
  const out = new Map<number, PieceState>();
  const info = new Map(scene.initial.map((p) => [p.id, p]));
  for (const p of scene.initial) sq.set(p.id, p.square);
  const base = (id: number): PieceState => {
    const p = info.get(id)!;
    return { id, type: p.type, color: p.color, x: 0, y: SURFACE_Y, z: 0, rotY: (p.type === 'n' || p.type === 'b') && p.color === 'w' ? Math.PI : 0, rotZ: 0, scale: 1 };
  };
  const overrides = new Map<number, Partial<PieceState>>();
  for (const mv of scene.moves) {
    if (frame < mv.start) break;
    const k = Math.min(1, (frame - mv.start) / mv.dur);
    const [ax, az] = sqToWorld(mv.from), [bx, bz] = sqToWorld(mv.to);
    if (k >= 1) {
      sq.set(mv.id, mv.to);
      if (mv.victimId) {
        // the captured piece is lifted away over 12 frames after the capturer has nearly arrived
        const vk = Math.min(1, Math.max(0, (frame - (mv.start + mv.dur * 0.85)) / 12));
        if (vk >= 1) gone.add(mv.victimId);
        else {
          const [vx, vz] = sqToWorld(mv.to);
          overrides.set(mv.victimId, { x: vx, y: SURFACE_Y + vk * 0.5, z: vz, scale: Math.max(0.0001, 1 - vk * vk), rotZ: vk * 0.7 });
          sq.set(mv.victimId, mv.to);
        }
      }
      continue;
    }
    const e = mv.slow ? easeLand(k) : easeInOut(k);
    overrides.set(mv.id, { x: ax + (bx - ax) * e, y: SURFACE_Y + Math.sin(Math.PI * e) * mv.arc, z: az + (bz - az) * e });
    if (mv.victimId) {
      const vk = Math.min(1, Math.max(0, (frame - (mv.start + mv.dur * 0.85)) / 12));
      const [vx, vz] = sqToWorld(mv.to);
      if (vk > 0) overrides.set(mv.victimId, { x: vx, y: SURFACE_Y + vk * 0.5, z: vz, scale: Math.max(0.0001, 1 - vk * vk), rotZ: vk * 0.7 });
      sq.set(mv.victimId, mv.to);
    }
  }
  for (const p of scene.initial) {
    if (gone.has(p.id)) continue;
    const s = base(p.id);
    const [x, z] = sqToWorld(sq.get(p.id)!);
    s.x = x;
    s.z = z;
    Object.assign(s, overrides.get(p.id));
    out.set(p.id, s);
  }
  // checkmate: the king shudders, then tips over the edge of its base, bounces once and lies still on the board
  if (scene.mate && frame >= scene.mate.start) {
    const king = out.get(scene.mate.kingId)!;
    const t = frame - scene.mate.start;
    const [dx, dz] = scene.mate.dir;
    if (t < SHUDDER_FRAMES) {
      const u = t / SHUDDER_FRAMES;
      king.rotZ = 0.045 * Math.sin(u * Math.PI * 6) * (0.3 + u);
      king.x += 0.014 * Math.sin(u * Math.PI * 9);
    } else {
      const fall = t - SHUDDER_FRAMES;
      let a: number;
      if (fall < FALL_FRAMES) a = (Math.PI / 2) * Math.pow(fall / FALL_FRAMES, 2.1);
      else {
        const v = Math.min(1, (fall - FALL_FRAMES) / SETTLE_FRAMES);
        a = Math.PI / 2 - 0.17 * Math.sin(Math.PI * v) * (1 - v);
      }
      // rotate about the base edge on the side the king falls towards
      const axis: [number, number, number] = [dz, 0, -dx]; // up x dir
      const rel = rot([-KING_RADIUS * dx, 0, -KING_RADIUS * dz], axis, a);
      king.x += KING_RADIUS * dx + rel[0];
      king.y = SURFACE_Y + rel[1];
      king.z += KING_RADIUS * dz + rel[2];
      const h = a / 2;
      king.q = [axis[0] * Math.sin(h), 0, axis[2] * Math.sin(h), Math.cos(h)];
    }
  }
  return [...out.values()];
}
