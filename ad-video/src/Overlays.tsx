// Typography and light effects that sit on top of the 3D stage.
import React from 'react';
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion';
import { SERIF } from './fonts';
import { useLayout } from './layout';

const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;

/** Scene 1: "THIS ISN'T ORDINARY CHESS." Words rise out of a blur one after another, then leave upwards. */
export const HookText: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { portrait, u, width, height, safe } = useLayout();
  const lines = portrait ? [["THIS", "ISN'T"], ['ORDINARY'], ['CHESS.']] : [["THIS", "ISN'T", 'ORDINARY'], ['CHESS.']];
  const size = portrait ? u * 0.115 : u * 0.115;
  const out = interpolate(f, [80, 94], [0, 1], clamp);
  let w = 0;
  return (
    <AbsoluteFill style={{ opacity: 1 - out, transform: `translateY(${-out * 30}px)` }}>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: height * 0.5, background: 'linear-gradient(to top, rgba(6,4,3,0.82) 0%, rgba(6,4,3,0.55) 45%, rgba(6,4,3,0))' }} />
      <div style={{ position: 'absolute', left: safe.side, right: safe.side, bottom: safe.bottom * (portrait ? 1.05 : 1.1), textAlign: 'center', fontFamily: SERIF, fontWeight: 700, color: '#fff7e8', fontSize: size, lineHeight: 1.12, letterSpacing: size * 0.08, textShadow: '0 4px 28px rgba(0,0,0,0.65)' }}>
        {lines.map((ln, li) => (
          <div key={li}>
            {ln.map((word, wi) => {
              const start = 20 + w * 7;
              w++;
              const k = spring({ frame: f - start, fps, config: { damping: 18, stiffness: 120 } });
              const gold = li === lines.length - 1;
              return (
                <span key={wi} style={{ display: 'inline-block', marginRight: size * 0.28, opacity: interpolate(f, [start, start + 8], [0, 1], clamp), transform: `translateY(${(1 - k) * size * 0.45}px)`, filter: `blur(${(1 - k) * 10}px)`, color: gold ? '#f3cf86' : '#fff7e8' }}>
                  {word}
                </span>
              );
            })}
          </div>
        ))}
        <div style={{ margin: `${size * 0.35}px auto 0`, height: Math.max(3, u * 0.003), width: interpolate(f, [44, 70], [0, width * (portrait ? 0.46 : 0.22)], clamp), background: 'linear-gradient(90deg, rgba(243,207,134,0), #f3cf86, rgba(243,207,134,0))' }} />
      </div>
    </AbsoluteFill>
  );
};

/** Scene 3: "CHECKMATE" at the decisive moment (frame 444 + 3). */
export const CheckmateText: React.FC<{ at: number; out: number }> = ({ at, out }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { portrait, u, width, safe } = useLayout();
  const k = spring({ frame: f - at, fps, config: { damping: 16, stiffness: 90 } });
  const alpha = interpolate(f, [at, at + 6, out, out + 10], [0, 1, 1, 0], clamp);
  const size = portrait ? u * 0.093 : u * 0.12;
  const spacing = interpolate(k, [0, 1], [size * 0.55, size * 0.1]);
  const flash = interpolate(f, [at - 1, at + 2, at + 14], [0, 0.35, 0], clamp);
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ background: 'radial-gradient(ellipse at center, rgba(255,235,210,0.9), rgba(255,200,160,0))', opacity: flash }} />
      <AbsoluteFill style={{ opacity: alpha }}>
        <div style={{ position: 'absolute', left: 0, right: 0, top: portrait ? safe.top + u * 0.1 : safe.top * 0.55, textAlign: 'center', fontFamily: SERIF, fontWeight: 900, fontSize: size, letterSpacing: spacing, paddingLeft: spacing, transform: `scale(${0.94 + 0.06 * k})`, background: 'linear-gradient(180deg, #fffaf0 0%, #f6dca0 55%, #c99a45 100%)', WebkitBackgroundClip: 'text', backgroundClip: 'text', color: 'transparent', filter: 'drop-shadow(0 0 22px rgba(225,60,40,0.55)) drop-shadow(0 6px 24px rgba(0,0,0,0.7))' }}>
          CHECKMATE
        </div>
        <div style={{ position: 'absolute', left: '50%', top: (portrait ? safe.top + u * 0.1 : safe.top * 0.55) + size * 1.3, height: Math.max(3, u * 0.003), width: interpolate(k, [0, 1], [0, width * (portrait ? 0.5 : 0.28)]), transform: 'translateX(-50%)', background: 'linear-gradient(90deg, rgba(225,60,40,0), #e1432e, rgba(225,60,40,0))' }} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** A diagonal band of warm light that crosses the frame (scene 3 -> 4 transition). */
export const LightSweep: React.FC<{ from: number; to: number; strength?: number }> = ({ from, to, strength = 0.85 }) => {
  const f = useCurrentFrame();
  const { width, height } = useLayout();
  const k = interpolate(f, [from, to], [0, 1], clamp);
  if (k <= 0 || k >= 1) return null;
  const x = interpolate(k, [0, 1], [-0.35, 1.35]) * (width + height);
  return (
    <AbsoluteFill style={{ opacity: strength * Math.sin(Math.PI * k), pointerEvents: 'none', mixBlendMode: 'screen' }}>
      <div style={{ position: 'absolute', left: x - width * 0.2, top: -height * 0.3, width: width * 0.4, height: height * 1.6, transform: 'rotate(18deg)', background: 'linear-gradient(90deg, rgba(255,214,150,0), rgba(255,226,170,0.9), rgba(255,214,150,0))', filter: 'blur(26px)' }} />
    </AbsoluteFill>
  );
};

/** Soft vignette over the 3D footage for focus and contrast. */
export const Vignette: React.FC<{ opacity?: number }> = ({ opacity = 1 }) => (
  <AbsoluteFill style={{ background: 'radial-gradient(ellipse at 50% 46%, rgba(0,0,0,0) 52%, rgba(0,0,0,0.55) 100%)', opacity, pointerEvents: 'none' }} />
);
