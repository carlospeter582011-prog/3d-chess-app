// Turns a list of chess moves into frame-accurate piece motion. It copies the app's own animation maths
// (arc height, ease-in-out, capture shrink, and the checkmate "king thrown off the board" effect) so the ad
// looks exactly like the game.
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
  scale: number;
}

export const SURFACE_Y = 0.464;
export const sqToWorld = (sq: string): [number, number] => [sq.charCodeAt(0) - 97 - 3.5, 3.5 - (sq.charCodeAt(1) - 49)];
const easeInOut = (k: number) => (k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2);

interface MoveEv {
  start: number;
  dur: number;
  id: number;
  type: PieceType;
  from: string;
  to: string;
  victimId?: number;
}

export interface SceneSpec {
  /** Start position (default: the normal starting position). */
  fen?: string;
  /** Moves in SAN, played one after the other. */
  sans: string[];
  /** Frames of stillness before the first move / after the last effect. */
  lead?: number;
  tail?: number;
  /** Pause between moves in ms. */
  pauseMs?: number;
  /** Slow the app's move speed by this factor (1 = same as the app). */
  slow?: number;
  /** What happens after the last move. */
  ending?: 'mate' | 'stalemate' | 'none';
}

export interface Scene {
  initial: { id: number; type: PieceType; color: Color; square: string }[];
  moves: MoveEv[];
  /** Frame the final move lands. */
  endMove: number;
  loserKingId?: number;
  throwStart?: number;
  sounds: { frame: number; name: 'move' | 'capture' | 'checkmate' | 'stalemate' }[];
  total: number;
  ending: 'mate' | 'stalemate' | 'none';
  /** Squares of the last move at each frame are not drawn: the ad shows only board and pieces. */
}

export const SHUDDER_FRAMES = ms(420);
export const THROW_FRAMES = ms(950);

export function buildScene(spec: SceneSpec): Scene {
  const chess = new Chess(spec.fen);
  const initial: Scene['initial'] = [];
  const idAt = new Map<string, number>();
  let nextId = 1;
  for (const row of chess.board())
    for (const sq of row) {
      if (!sq) continue;
      initial.push({ id: nextId, type: sq.type as PieceType, color: sq.color as Color, square: sq.square });
      idAt.set(sq.square, nextId++);
    }
  const slow = spec.slow ?? 1;
  const lead = spec.lead ?? 20;
  const pause = ms(spec.pauseMs ?? 500);
  const moves: MoveEv[] = [];
  const sounds: Scene['sounds'] = [];
  const typeOf = new Map(initial.map((p) => [p.id, p.type]));
  let t = lead;
  let end = 0;
  for (const san of spec.sans) {
    const m = chess.move(san);
    if (m.flags.includes('e') || m.flags.includes('k') || m.flags.includes('q') || m.promotion)
      throw new Error(`special move ${san} is not supported by the ad timeline`);
    const id = idAt.get(m.from)!;
    const victimId = m.captured ? idAt.get(m.to) : undefined;
    const [ax, az] = sqToWorld(m.from), [bx, bz] = sqToWorld(m.to);
    const dist = Math.hypot(ax - bx, az - bz);
    const dur = ms(Math.min(700, 280 + dist * 70)) * slow;
    moves.push({ start: t, dur, id, type: typeOf.get(id)!, from: m.from, to: m.to, victimId });
    sounds.push({ frame: Math.round(t), name: m.captured ? 'capture' : 'move' });
    idAt.delete(m.from);
    idAt.set(m.to, id);
    end = t + dur;
    t = end + pause;
  }
  const ending = spec.ending ?? 'none';
  const scene: Scene = { initial, moves, endMove: end, sounds, total: 0, ending };
  let finish = end;
  if (ending === 'mate' && chess.isCheckmate()) {
    const loser = chess.turn();
    scene.loserKingId = initial.find((p) => p.type === 'k' && p.color === loser)!.id;
    scene.throwStart = end;
    sounds.push({ frame: Math.round(end), name: 'checkmate' });
    finish = end + SHUDDER_FRAMES + THROW_FRAMES;
  } else if (ending === 'stalemate' && chess.isStalemate()) {
    sounds.push({ frame: Math.round(end), name: 'stalemate' });
  } else if (ending !== 'none') {
    throw new Error(`the moves do not end in ${ending}`);
  }
  scene.total = Math.ceil(finish + (spec.tail ?? 60));
  return scene;
}

/** Piece positions at a (scene-local) frame. */
export function stateAt(scene: Scene, frame: number): PieceState[] {
  const sq = new Map<number, string>();
  const gone = new Set<number>();
  const out = new Map<number, PieceState>();
  for (const p of scene.initial) sq.set(p.id, p.square);
  const base = (id: number): PieceState => {
    const p = scene.initial.find((q) => q.id === id)!;
    return { id, type: p.type, color: p.color, x: 0, y: SURFACE_Y, z: 0, rotY: (p.type === 'n' || p.type === 'b') && p.color === 'w' ? Math.PI : 0, rotZ: 0, scale: 1 };
  };
  const overrides = new Map<number, Partial<PieceState>>();
  for (const mv of scene.moves) {
    if (frame < mv.start) break;
    const k = Math.min(1, (frame - mv.start) / mv.dur);
    const [ax, az] = sqToWorld(mv.from), [bx, bz] = sqToWorld(mv.to);
    if (k >= 1) {
      sq.set(mv.id, mv.to);
      if (mv.victimId) gone.add(mv.victimId);
      continue;
    }
    const e = easeInOut(k);
    const arc = mv.type === 'n' ? 0.9 : 0.28;
    overrides.set(mv.id, { x: ax + (bx - ax) * e, y: SURFACE_Y + Math.sin(Math.PI * e) * arc, z: az + (bz - az) * e });
    if (mv.victimId) {
      const vk = Math.min(1, Math.max(0, (frame - (mv.start + mv.dur * 0.6)) / ms(320)));
      const [vx, vz] = sqToWorld(mv.to);
      if (vk >= 1) gone.add(mv.victimId);
      else overrides.set(mv.victimId, { x: vx, y: SURFACE_Y + vk * 0.7, z: vz, scale: Math.max(0.0001, 1 - vk), rotZ: vk * 0.9 });
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
  // checkmate: the losing king shudders, then is thrown off the board
  if (scene.loserKingId && scene.throwStart !== undefined && frame >= scene.throwStart) {
    const k = out.get(scene.loserKingId)!;
    const t = frame - scene.throwStart;
    const sx = k.x, sz = k.z;
    let dx = sx, dz = sz;
    const len = Math.hypot(dx, dz);
    if (len < 0.5) { dx = 1; dz = 0; } else { dx /= len; dz /= len; }
    if (t < SHUDDER_FRAMES) {
      const u = t / SHUDDER_FRAMES;
      k.rotZ = 0.07 * Math.sin(u * Math.PI * 7) * (0.4 + u);
      k.x = sx + dx * 0.02 * Math.sin(u * Math.PI * 11);
    } else {
      const u = Math.min(1, (t - SHUDDER_FRAMES) / THROW_FRAMES);
      k.x = sx + dx * 4.2 * u;
      k.z = sz + dz * 4.2 * u;
      k.y = SURFACE_Y + 4 * 1.9 * u * (1 - u) + 0.3 * u;
      k.rotZ = u * Math.PI * 2.6;
      k.scale = u < 0.75 ? 1 : Math.max(0.0001, 1 - (u - 0.75) / 0.25);
    }
  }
  return [...out.values()];
}
