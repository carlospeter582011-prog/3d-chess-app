// The 3D stage: the game's real GLB board, table and 12 piece models, cinematic lighting and the camera rig.
// Everything is a pure function of the frame number, so renders are deterministic.
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { ThreeCanvas } from '@remotion/three';
import { useThree } from '@react-three/fiber';
import { cancelRender, continueRender, delayRender, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { Cam } from './camera';
import { PieceState, Scene, stateAt } from './timeline';

const NAMES: Record<string, string> = { k: 'king', q: 'queen', r: 'rook', b: 'bishop', n: 'knight', p: 'pawn' };
const FILES = ['board', 'table', ...Object.keys(NAMES).flatMap((t) => [`${NAMES[t]}_light`, `${NAMES[t]}_dark`])];
const cache = new Map<string, THREE.Object3D>();

const modelFile = (type: string, color: string) => `${NAMES[type]}_${color === 'w' ? 'light' : 'dark'}`;

/** Loads every model and holds the render until each one is in the cache and has been drawn a few times. */
export function useModels(): boolean {
  const [ready, setReady] = useState(cache.size >= FILES.length);
  const [handle] = useState(() => (cache.size >= FILES.length ? null : delayRender('loading 3D models', { timeoutInMilliseconds: 180000 })));
  useEffect(() => {
    if (cache.size >= FILES.length) return;
    const loader = new GLTFLoader();
    Promise.all(
      FILES.map((f) => new Promise<void>((res, rej) => loader.load(staticFile(`models/${f}.glb`), (g) => { cache.set(f, g.scene); res(); }, undefined, rej))),
    )
      .then(() => setReady(true))
      .catch((e) => cancelRender(e));
  }, []);
  useEffect(() => {
    if (!ready || handle === null) return;
    let n = 0;
    const tick = () => (++n < 6 ? requestAnimationFrame(tick) : continueRender(handle));
    requestAnimationFrame(tick);
  }, [ready, handle]);
  return ready;
}

function prep(obj: THREE.Object3D, cast: boolean, receive: boolean) {
  obj.traverse((o) => {
    if ((o as THREE.Mesh).isMesh) { o.castShadow = cast; o.receiveShadow = receive; }
  });
  return obj;
}

const Piece: React.FC<{ p: PieceState }> = ({ p }) => {
  const obj = useMemo(() => prep(cache.get(modelFile(p.type, p.color))!.clone(true), true, true), [p.type, p.color]);
  const quat = p.q ? new THREE.Quaternion(p.q[0], p.q[1], p.q[2], p.q[3]) : undefined;
  return (
    <group position={[p.x, p.y, p.z]} rotation={quat ? undefined : new THREE.Euler(0, p.rotY, p.rotZ, 'YXZ')} quaternion={quat ? quat.multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), p.rotY)) : undefined} scale={p.scale}>
      <primitive object={obj} />
    </group>
  );
};

export interface LightMood {
  key: number;
  fill: number;
  rim: number;
  rimColor: string;
  /** checkmate emphasis: spotlight on the duel + subtle red accent, 0..1 */
  hero: number;
  red: number;
  exposure: number;
}

const smooth = (a: number, b: number, f: number) => { const k = Math.min(1, Math.max(0, (f - a) / (b - a))); return k * k * (3 - 2 * k); };

/** Lighting plan: strong golden rim in the hook, balanced in the battle, tension, then the checkmate emphasis. */
export function moodAt(frame: number, mateFrame: number): LightMood {
  const hookRim = 1 - smooth(40, 110, frame);
  const mate = smooth(mateFrame, mateFrame + 22, frame);
  const tension = smooth(336, mateFrame, frame);
  return {
    key: 640 * (1 - 0.5 * hookRim) * (1 - 0.22 * tension) * (1 - 0.3 * mate),
    fill: 0.34 * (1 - 0.25 * tension),
    rim: 300 + 520 * hookRim + 220 * tension,
    rimColor: hookRim > 0.15 ? '#ffb347' : '#ffc67a',
    hero: mate,
    red: mate * (1 - 0.15 * smooth(mateFrame + 60, mateFrame + 66, frame)),
    exposure: 1.0 + 0.08 * hookRim,
  };
}

const Rig: React.FC<{ cam: Cam; aspect: number }> = ({ cam, aspect }) => {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  camera.position.set(...cam.pos);
  camera.fov = cam.fov;
  camera.aspect = aspect;
  camera.near = 0.2;
  camera.far = 200;
  camera.lookAt(...cam.look);
  camera.updateProjectionMatrix();
  camera.updateMatrixWorld();
  return null;
};

const Inner: React.FC<{ scene: Scene; frame: number; cam: Cam; mood: LightMood; width: number; height: number }> = ({ scene, frame, cam, mood, width, height }) => {
  const pieces = useMemo(() => stateAt(scene, frame), [scene, frame]);
  const table = useMemo(() => prep(cache.get('table')!.clone(true), false, true), []);
  const board = useMemo(() => prep(cache.get('board')!.clone(true), false, true), []);
  const rim = useMemo(() => { const l = new THREE.SpotLight('#ffb347', 500, 0, 0.3, 0.9, 2); return l; }, []);
  const hero = useMemo(() => { const l = new THREE.SpotLight('#fff1d6', 0, 0, 0.34, 0.85, 2); l.castShadow = true; l.shadow.mapSize.set(1024, 1024); l.shadow.bias = -0.0004; return l; }, []);
  const king = scene.mate ? pieces.find((p) => p.id === scene.mate!.kingId) : undefined;
  const kx = king?.x ?? 0, kz = king?.z ?? 0;
  // rim light sits behind the subject relative to the camera, so every shot gets a golden edge
  const dx = cam.look[0] - cam.pos[0], dz = cam.look[2] - cam.pos[2];
  const dl = Math.hypot(dx, dz) || 1;
  rim.position.set(cam.look[0] + (dx / dl) * 5 - (dz / dl) * 2.2, cam.look[1] + 3.2, cam.look[2] + (dz / dl) * 5 + (dx / dl) * 2.2);
  rim.target.position.set(cam.look[0], cam.look[1], cam.look[2]);
  rim.target.updateMatrixWorld();
  rim.color.set(mood.rimColor);
  rim.intensity = mood.rim;
  hero.position.set(kx + 1.2, 7.5, kz + 3.2);
  hero.target.position.set(kx - 0.1, 0.9, kz + 0.9);
  hero.target.updateMatrixWorld();
  hero.intensity = 380 * mood.hero;
  return (
    <>
      <Rig cam={cam} aspect={width / height} />
      <color attach="background" args={['#0a0806']} />
      <fog attach="fog" args={['#0a0806', 16, 46]} />
      <ambientLight intensity={0.05} color="#ffe8cc" />
      <hemisphereLight args={['#fff3e4', '#1a120b', mood.fill]} />
      <spotLight position={[-4.5, 12.5, 7.5]} angle={0.62} penumbra={1} intensity={mood.key} color="#fff6ea" castShadow shadow-mapSize={[2048, 2048]} shadow-bias={-0.0003} shadow-camera-near={5} shadow-camera-far={40} />
      <primitive object={rim} />
      <primitive object={rim.target} />
      <primitive object={hero} />
      <primitive object={hero.target} />
      <pointLight position={[kx, 1.9, kz + 0.6]} color="#ff2b1c" intensity={26 * mood.red} distance={5.5} decay={2} />
      <primitive object={table} />
      <primitive object={board} />
      {pieces.map((p) => <Piece key={p.id} p={p} />)}
    </>
  );
};

export const Stage: React.FC<{ scene: Scene; camAt: (frame: number, pieces: PieceState[]) => Cam; moodAt: (frame: number) => LightMood; frameOffset?: number; width?: number; height?: number }> = ({ scene, camAt, moodAt: mood, frameOffset = 0, width: w, height: h }) => {
  const local = useCurrentFrame();
  const frame = local + frameOffset;
  const cfg = useVideoConfig();
  const width = w ?? cfg.width, height = h ?? cfg.height;
  const ready = useModels();
  const cam = useMemo(() => camAt(frame, stateAt(scene, frame)), [camAt, scene, frame]);
  const m = mood(frame);
  const ref = useRef<HTMLDivElement>(null);
  return (
    <div ref={ref} style={{ position: 'absolute', left: 0, top: 0, width, height, background: '#0a0806' }}>
      {ready && (
        <ThreeCanvas width={width} height={height} shadows gl={{ antialias: true, toneMapping: THREE.ACESFilmicToneMapping, toneMappingExposure: m.exposure }}>
          <Inner scene={scene} frame={frame} cam={cam} mood={m} width={width} height={height} />
        </ThreeCanvas>
      )}
    </div>
  );
};
