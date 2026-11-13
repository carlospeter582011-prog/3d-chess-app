// Scene 4: the gameplay reveal. The app's screens (AppScreens.tsx) inside a CSS-3D smartphone that floats in with a
// slow, smooth camera-like rotation, with one feature callout at a time.
import React from 'react';
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion';
import { GameScreen, MenuScreen, SCREEN_H, SCREEN_W } from './AppScreens';
import { SANS, SERIF } from './fonts';
import { useLayout } from './layout';

const PW = SCREEN_W + 28, PH = SCREEN_H + 28;
const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;
const ease = (k: number) => k * k * (3 - 2 * k);

/** Feature callouts: every claim is backed by the app's source (menu.dart, hud.dart, orbit_camera.dart). */
export const FEATURES = [
  { a: 2, b: 54, title: 'Play the computer', sub: 'Stockfish runs on your device · 400–3200 Elo' },
  { a: 57, b: 102, title: '2 players, 1 phone', sub: 'Pass it back and forth · no internet needed' },
  { a: 105, b: 148, title: 'A fully 3D board', sub: 'Real Staunton pieces on a real 3D table' },
  { a: 151, b: 190, title: 'Every angle', sub: 'Orbit, zoom and switch to the top view' },
];

const Chips: React.FC<{ lf: number }> = ({ lf }) => {
  const { portrait, u, width, height, safe } = useLayout();
  const idx = FEATURES.findIndex((x) => lf >= x.a && lf < x.b + 8);
  return (
    <div style={{ position: 'absolute', left: portrait ? safe.side : width * 0.065, width: portrait ? width - 2 * safe.side : width * 0.45, top: portrait ? safe.top + height * 0.012 : height * 0.5 - u * 0.17, textAlign: portrait ? 'center' : 'left', height: portrait ? height * 0.16 : u * 0.34 }}>
      {FEATURES.map((x, i) => {
        const o = interpolate(lf, [x.a, x.a + 9, x.b - 2, x.b + 6], [0, 1, 1, 0], clamp);
        if (o <= 0) return null;
        const rise = (1 - ease(Math.min(1, Math.max(0, (lf - x.a) / 12)))) * u * 0.03;
        return (
          <div key={i} style={{ position: 'absolute', left: 0, right: 0, top: 0, opacity: o, transform: `translateY(${rise}px)`, filter: `blur(${(1 - o) * 6}px)` }}>
            <div style={{ fontFamily: SERIF, fontWeight: 700, color: '#fff3dc', fontSize: portrait ? u * 0.066 : u * 0.062, letterSpacing: u * 0.004, lineHeight: 1.15, textShadow: '0 4px 24px rgba(0,0,0,0.6)' }}>{x.title}</div>
            <div style={{ fontFamily: SANS, fontWeight: 400, color: '#cdbb98', fontSize: portrait ? u * 0.03 : u * 0.03, marginTop: u * 0.014, lineHeight: 1.4 }}>{x.sub}</div>
          </div>
        );
      })}
      <div style={{ position: 'absolute', left: portrait ? '50%' : 0, transform: portrait ? 'translateX(-50%)' : undefined, top: portrait ? height * 0.115 : u * 0.3, display: 'flex', gap: u * 0.014 }}>
        {FEATURES.map((_, i) => <div key={i} style={{ width: i === idx ? u * 0.05 : u * 0.012, height: u * 0.006, borderRadius: u, background: i === idx ? '#f3d08a' : 'rgba(243,208,138,0.3)' }} />)}
      </div>
    </div>
  );
};

export const PhoneScene: React.FC = () => {
  const f = useCurrentFrame();
  const lf = f - 5; // lf = frames since the gameplay scene started (film frame 510)
  const { fps } = useVideoConfig();
  const { portrait, width, height } = useLayout();
  const S = portrait ? 1.14 : 1.0;
  const cx = portrait ? width * 0.5 : width * 0.69;
  const cy = portrait ? height * 0.54 : height * 0.5;
  const enter = spring({ frame: f - 2, fps, config: { damping: 20, stiffness: 70 } });
  const t = Math.max(0, lf) / 190;
  const ry = interpolate(enter, [0, 1], [-52, -20]) + 38 * ease(Math.min(1, t)) + 4 * Math.sin(lf / 24);
  const rx = interpolate(enter, [0, 1], [10, 6]) - 6 * ease(Math.min(1, t)) + 1.2 * Math.sin(lf / 31);
  const ty = (1 - enter) * height * 0.22 + 6 * Math.sin(lf / 20);
  const sc = 0.82 + 0.18 * enter;
  const fadeIn = interpolate(f, [0, 16], [0, 1], clamp);
  const gameFade = interpolate(lf, [92, 108], [0, 1], clamp);
  const layers = Array.from({ length: 9 }, (_, i) => -9 + i * 2);
  return (
    <AbsoluteFill style={{ opacity: fadeIn, background: 'radial-gradient(ellipse at 60% 45%, #2a1e13 0%, #100b08 55%, #070504 100%)' }}>
      <AbsoluteFill style={{ background: `radial-gradient(circle at ${(cx / width) * 100}% ${(cy / height) * 100}%, rgba(243,208,138,0.22), rgba(243,208,138,0) 42%)` }} />
      <Chips lf={lf} />
      <div style={{ position: 'absolute', left: cx - PW * 0.55 * S, top: cy + PH * 0.5 * S - 8, width: PW * 1.1 * S, height: 70 * S, borderRadius: '50%', background: 'radial-gradient(ellipse, rgba(0,0,0,0.65), rgba(0,0,0,0) 70%)', filter: 'blur(14px)', opacity: enter }} />
      <div style={{ position: 'absolute', inset: 0, perspective: 2400, perspectiveOrigin: `${cx}px ${cy}px` }}>
        <div style={{ position: 'absolute', left: cx - PW / 2, top: cy - PH / 2, width: PW, height: PH, transformStyle: 'preserve-3d', transform: `translateY(${ty}px) scale(${S * sc}) rotateX(${rx}deg) rotateY(${ry}deg)` }}>
          {layers.map((z, i) => (
            <div key={i} style={{ position: 'absolute', inset: 0, borderRadius: 66, background: `linear-gradient(135deg, #3a3a3f, #17171a ${40 + i * 3}%, #2a2a2e)`, transform: `translateZ(${z}px)` }} />
          ))}
          <div style={{ position: 'absolute', inset: 0, borderRadius: 66, background: '#09090a', transform: 'translateZ(10px)', boxShadow: 'inset 0 0 0 2px #47474c, inset 0 0 0 3.5px rgba(255,214,150,0.28)' }}>
            <div style={{ position: 'absolute', left: 14, top: 14, width: SCREEN_W, height: SCREEN_H, borderRadius: 52, overflow: 'hidden', background: '#000' }}>
              <div style={{ position: 'absolute', inset: 0, opacity: 1 - gameFade }}><MenuScreen lf={lf} /></div>
              {lf >= 86 && <GameScreen lf={lf} fadeIn={gameFade} />}
              <div style={{ position: 'absolute', left: '50%', top: 12, width: 104, height: 30, marginLeft: -52, borderRadius: 16, background: '#000' }} />
              <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(${112 + ry * 0.6}deg, rgba(255,255,255,0) ${30 - ry * 0.4}%, rgba(255,255,255,0.1) ${44 - ry * 0.4}%, rgba(255,255,255,0) ${58 - ry * 0.4}%)`, pointerEvents: 'none' }} />
            </div>
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
