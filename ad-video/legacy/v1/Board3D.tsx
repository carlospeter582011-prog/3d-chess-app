// The 3D board: the game's real GLB models (board, table, 12 pieces) rendered with three.js inside Remotion.
// Only board and pieces are drawn: no highlights, move list or any other UI.
import React, { useEffect, useMemo, useState } from 'react';
import { ThreeCanvas } from '@remotion/three';
import { useThree } from '@react-three/fiber';
import { cancelRender, continueRender, delayRender, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { PieceState, Scene, stateAt } from './timeline';

const NAMES: Record<string, string> = { k: 'king', q: 'queen', r: 'rook', b: 'bishop', n: 'knight', p: 'pawn' };
const cache = new Map<string, THREE.Object3D>();

function modelFile(type: string, color: string) {
  return `${NAMES[type]}_${color === 'w' ? 'light' : 'dark'}`;
}

function useModels(): boolean {
  const [ready, setReady] = useState(cache.size >= 14);
  const [handle] = useState(() => (cache.size >= 14 ? null : delayRender('loading 3D models', { timeoutInMilliseconds: 120000 })));
  useEffect(() => {
    if (cache.size >= 14) return;
    const loader = new GLTFLoader();
    const files = ['board', 'table', ...Object.keys(NAMES).flatMap((t) => [modelFile(t, 'w'), modelFile(t, 'b')])];
    Promise.all(
      files.map(
        (f) =>
          new Promise<void>((res, rej) =>
            loader.load(staticFile(`models/${f}.glb`), (g) => { cache.set(f, g.scene); res(); }, undefined, rej),
          ),
      ),
    )
      .then(() => setReady(true))
      .catch((e) => cancelRender(e));
  }, []);
  // let the canvas draw a few frames with the models before Remotion takes the screenshot
  useEffect(() => {
    if (!ready || handle === null) return;
    let n = 0;
    const tick = () => (++n < 4 ? requestAnimationFrame(tick) : continueRender(handle));
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
  return (
    <group position={[p.x, p.y, p.z]} rotation={new THREE.Euler(0, p.rotY, p.rotZ, 'YXZ')} scale={p.scale}>
      <primitive object={obj} />
    </group>
  );
};

export interface CameraSpec {
  /** Orbit angle around the board in radians (0 = White's side). */
  theta: number;
  /** Angle from straight-down in degrees. */
  phi: number;
  /** Multiplier on the distance that fits the board to the screen width. */
  zoom: number;
}

const Inner: React.FC<{ scene: Scene | null; frame: number; cam: CameraSpec; width: number; height: number }> = ({ scene, frame, cam, width, height }) => {
  const pieces = useMemo(() => (scene ? stateAt(scene, frame) : initialPieces()), [scene, frame]);
  const aspect = width / height;
  const fov = 32;
  const hHalf = Math.atan(Math.tan((fov * Math.PI) / 360) * aspect);
  const vHalf = (fov * Math.PI) / 360;
  // fit the board to both the width and the height of the frame
  const dist = Math.max((aspect < 1 ? 5.7 : 6.4) / Math.tan(hHalf), 5.5 / Math.tan(vHalf)) * cam.zoom;
  const phi = (cam.phi * Math.PI) / 180;
  const cx = Math.sin(cam.theta) * Math.sin(phi) * dist;
  const cz = Math.cos(cam.theta) * Math.sin(phi) * dist;
  const cy = Math.cos(phi) * dist + 0.5;
  const camera = useThree((st) => st.camera) as THREE.PerspectiveCamera;
  React.useLayoutEffect(() => {
    camera.position.set(cx, cy, cz);
    camera.fov = fov;
    camera.aspect = aspect;
    camera.near = 1;
    camera.far = 200;
    camera.lookAt(0, 0.5, 0);
    camera.updateProjectionMatrix();
  }, [camera, cx, cy, cz, aspect]);
  return (
    <>
      <color attach="background" args={['#15110e']} />
      <hemisphereLight args={['#ffe9cf', '#2a1f17', 1.1]} />
      <directionalLight position={[-6, 13, 9]} intensity={3.1} color="#fff0dc" castShadow shadow-mapSize={[2048, 2048]} shadow-camera-left={-7} shadow-camera-right={7} shadow-camera-top={7} shadow-camera-bottom={-7} shadow-camera-near={1} shadow-camera-far={40} shadow-bias={-0.0004} />
      <directionalLight position={[8, 6, -9]} intensity={0.9} color="#ffd7b0" />
      <primitive object={prep(cache.get('table')!, false, true)} />
      <primitive object={prep(cache.get('board')!, false, true)} />
      {pieces.map((p) => <Piece key={p.id} p={p} />)}
    </>
  );
};

function initialPieces(): PieceState[] {
  const back: ('r' | 'n' | 'b' | 'q' | 'k')[] = ['r', 'n', 'b', 'q', 'k', 'b', 'n', 'r'];
  const out: PieceState[] = [];
  let id = 1;
  for (let f = 0; f < 8; f++)
    for (const [color, rank, type] of [['w', 0, back[f]], ['w', 1, 'p'], ['b', 7, back[f]], ['b', 6, 'p']] as const)
      out.push({ id: id++, type, color, x: f - 3.5, y: 0.464, z: 3.5 - rank, rotY: (type === 'n' || type === 'b') && color === 'w' ? Math.PI : 0, rotZ: 0, scale: 1 });
  return out;
}

/** [scene] null shows the start position (used behind the intro). */
export const Board3D: React.FC<{ scene: Scene | null; cam: (frame: number) => CameraSpec }> = ({ scene, cam }) => {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const ready = useModels();
  return (
    <>
      {ready && (
        <ThreeCanvas width={width} height={height} shadows gl={{ antialias: true, toneMapping: THREE.ACESFilmicToneMapping, toneMappingExposure: 1.05 }}>
          <Inner scene={scene} frame={frame} cam={cam(frame)} width={width} height={height} />
        </ThreeCanvas>
      )}
    </>
  );
};
