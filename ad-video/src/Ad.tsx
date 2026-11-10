import React from 'react';
import { AbsoluteFill, Audio, Img, interpolate, Sequence, spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { Board3D, CameraSpec } from './Board3D';
import { Scene } from './timeline';
import { mateScene, playScene, staleScene } from './scenes';

const FONT = 'Inter, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif';
const INTRO = 130;
const END = 140;
export const AD_FRAMES = INTRO + playScene.total + mateScene.total + staleScene.total + END;

const fade = (frame: number, total: number, edge = 10) =>
  interpolate(frame, [0, edge, total - edge, total], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });

const useCam = (portrait: boolean) => (base: number, sway: number, total: number) => (f: number): CameraSpec => ({
  theta: base * (portrait ? 0.5 : 1) + Math.sin((f / total) * Math.PI * 2) * sway * (portrait ? 0.45 : 1),
  phi: portrait ? 44 : 52,
  zoom: portrait ? 1.0 : 1.0,
});

const BoardScene: React.FC<{ scene: Scene; sway: number; base?: number }> = ({ scene, sway, base = 0 }) => {
  const { width, height } = useCurrentFrameSize();
  const cam = useCam(height > width)(base, sway, scene.total);
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ opacity: fade(frame, scene.total) }}>
      <Board3D scene={scene} cam={cam} />
      {scene.sounds.map((s, i) => (
        <Sequence key={i} from={s.frame} layout="none">
          <Audio src={staticFile(`sfx/${s.name}.${s.name === 'checkmate' || s.name === 'stalemate' ? 'mp3' : 'wav'}`)} volume={s.name === 'move' || s.name === 'capture' ? 0.8 : 1} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};

function useCurrentFrameSize() {
  const { width, height } = useVideoConfig();
  return { width, height };
}

const Logo: React.FC<{ size: number }> = ({ size }) => (
  <Img src={staticFile('icon.png')} style={{ width: size, height: size, borderRadius: size * 0.22, boxShadow: '0 20px 60px rgba(0,0,0,0.55)' }} />
);

const Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const portrait = height > width;
  const u = Math.min(width, height);
  const pop = spring({ frame: frame - 8, fps, config: { damping: 14 } });
  const line = (start: number) => ({
    opacity: interpolate(frame, [start, start + 14], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }),
    transform: `translateY(${interpolate(frame, [start, start + 14], [24, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })}px)`,
  });
  return (
    <AbsoluteFill style={{ opacity: fade(frame, INTRO) }}>
      <Board3D scene={null} cam={(f) => ({ theta: -0.5 + (f / INTRO) * 0.9, phi: portrait ? 44 : 52, zoom: 1.0 })} />
      <AbsoluteFill style={{ background: 'radial-gradient(ellipse at center, rgba(15,11,8,0.82) 0%, rgba(15,11,8,0.72) 55%, rgba(15,11,8,0.5) 100%)' }} />
      <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', fontFamily: FONT, color: '#fff', textAlign: 'center', padding: u * 0.06 }}>
        <div style={{ transform: `scale(${pop})` }}><Logo size={u * (portrait ? 0.34 : 0.3)} /></div>
        <div style={{ ...line(22), fontSize: u * 0.11, fontWeight: 800, letterSpacing: -2, marginTop: u * 0.05 }}>3D Chess</div>
        <div style={{ ...line(40), fontSize: u * 0.05, fontWeight: 600, color: '#f3d9a8', marginTop: u * 0.015 }}>Chess on a real 3D board</div>
        <div style={{ ...line(62), fontSize: u * 0.038, color: '#e6ded4', marginTop: u * 0.04, lineHeight: 1.35 }}>
          Play the computer at your level,<br />or challenge a friend on one phone.
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const PlayBadge: React.FC<{ u: number }> = ({ u }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: u * 0.025, background: '#000', border: `${Math.max(2, u * 0.003)}px solid #a6a6a6`, borderRadius: u * 0.025, padding: `${u * 0.02}px ${u * 0.04}px`, color: '#fff' }}>
    <svg width={u * 0.07} height={u * 0.07} viewBox="0 0 24 24">
      <path d="M3 2.5v19l10-9.5z" fill="#00d2ff" />
      <path d="M3 2.5l13.5 7.7-3.5 1.8z" fill="#00f076" />
      <path d="M3 21.5L16.5 13.8 13 12z" fill="#ff3a44" />
      <path d="M16.5 10.2l4 2.3-4 2.3-3.5-1.8z" fill="#ffd500" />
    </svg>
    <div style={{ textAlign: 'left', lineHeight: 1.05 }}>
      <div style={{ fontSize: u * 0.026, letterSpacing: 1.5, textTransform: 'uppercase' }}>Download on</div>
      <div style={{ fontSize: u * 0.058, fontWeight: 600 }}>Google Play</div>
    </div>
  </div>
);

const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const u = Math.min(width, height);
  const pop = spring({ frame: frame - 6, fps, config: { damping: 14 } });
  const rise = (s: number) => ({
    opacity: interpolate(frame, [s, s + 14], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }),
    transform: `translateY(${interpolate(frame, [s, s + 14], [26, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })}px)`,
  });
  const pulse = 1 + 0.03 * Math.sin(frame / 6);
  return (
    <AbsoluteFill style={{ opacity: interpolate(frame, [0, 12], [0, 1], { extrapolateRight: 'clamp' }), background: 'radial-gradient(ellipse at 50% 35%, #3a2a1c 0%, #15110e 70%)', alignItems: 'center', justifyContent: 'center', fontFamily: FONT, color: '#fff', textAlign: 'center' }}>
      <div style={{ transform: `scale(${pop})` }}><Logo size={u * (height > width ? 0.3 : 0.26)} /></div>
      <div style={{ ...rise(18), fontSize: u * 0.1, fontWeight: 800, letterSpacing: -2, marginTop: u * 0.045 }}>3D Chess</div>
      <div style={{ ...rise(32), fontSize: u * 0.04, color: '#f3d9a8', marginTop: u * 0.012 }}>Play chess in 3D</div>
      <div style={{ ...rise(50), marginTop: u * 0.07, transform: `${rise(50).transform} scale(${pulse})` }}><PlayBadge u={u} /></div>
    </AbsoluteFill>
  );
};

export const Ad: React.FC = () => {
  let t = 0;
  const at = (n: number) => { const s = t; t += n; return s; };
  return (
    <AbsoluteFill style={{ background: '#15110e' }}>
      <Sequence from={at(INTRO)} durationInFrames={INTRO}><Intro /></Sequence>
      <Sequence from={at(playScene.total)} durationInFrames={playScene.total}><BoardScene scene={playScene} sway={0.3} base={0.1} /></Sequence>
      <Sequence from={at(mateScene.total)} durationInFrames={mateScene.total}><BoardScene scene={mateScene} sway={0.25} base={-0.15} /></Sequence>
      <Sequence from={at(staleScene.total)} durationInFrames={staleScene.total}><BoardScene scene={staleScene} sway={0.3} base={0.2} /></Sequence>
      <Sequence from={at(END)} durationInFrames={END}><EndCard /></Sequence>
    </AbsoluteFill>
  );
};
