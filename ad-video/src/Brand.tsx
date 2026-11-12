// Scene 5: final branding. Premium dark card: the app's real icon, wordmark with a golden light sweep, tagline, PLAY NOW.
// No store badge: the ad does not claim a store listing.
import React from 'react';
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { SANS, SERIF } from './fonts';
import { useLayout } from './layout';

const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;

export const BRAND_LOCAL = 4; // the card starts at film frame 690, 4 frames after its Sequence begins (cross-dissolve)

export const Brand: React.FC = () => {
  const f = useCurrentFrame();
  const bf = f - BRAND_LOCAL;
  const { fps } = useVideoConfig();
  const { portrait, u, width, height } = useLayout();
  const fadeIn = interpolate(f, [0, 12], [0, 1], clamp);
  const icon = spring({ frame: bf - 2, fps, config: { damping: 14, stiffness: 80 } });
  const iconSize = u * (portrait ? 0.36 : 0.3);
  const ring = interpolate(bf, [4, 46], [0.55, 1.5], clamp);
  const ringO = interpolate(bf, [4, 14, 46], [0, 0.7, 0], clamp);
  const word = 'CHESS';
  const wmSize = u * (portrait ? 0.118 : 0.12);
  const sweep = interpolate(bf, [34, 70], [-30, 130], clamp);
  const tag = interpolate(bf, [52, 66], [0, 1], clamp);
  const btn = spring({ frame: bf - 76, fps, config: { damping: 13, stiffness: 100 } });
  const glow = 0.5 + 0.5 * Math.sin(Math.max(0, bf - 80) / 9);
  return (
    <AbsoluteFill style={{ opacity: fadeIn, background: 'radial-gradient(ellipse at 50% 38%, #2b1f14 0%, #130d09 55%, #060403 100%)', alignItems: 'center', justifyContent: 'center', flexDirection: 'column' }}>
      <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ position: 'absolute', top: height * (portrait ? 0.33 : 0.34), width: iconSize * 1.2, height: iconSize * 1.2, marginTop: -iconSize * 0.6, borderRadius: '50%', border: `${Math.max(2, u * 0.003)}px solid #e3b45e`, transform: `scale(${ring})`, opacity: ringO }} />
      </AbsoluteFill>
      <div style={{ position: 'absolute', top: height * (portrait ? 0.33 : 0.34), transform: `translateY(-50%) scale(${0.55 + 0.45 * icon})`, opacity: Math.min(1, icon * 1.5), filter: `drop-shadow(0 0 ${u * 0.05}px rgba(227,180,94,0.35))` }}>
        <Img src={staticFile('icon.png')} style={{ width: iconSize, height: iconSize, borderRadius: iconSize * 0.22, display: 'block' }} />
      </div>
      <div style={{ position: 'absolute', top: height * (portrait ? 0.33 : 0.34) + iconSize * 0.62, width, textAlign: 'center' }}>
        <div style={{ fontFamily: SERIF, fontWeight: 900, fontSize: wmSize, lineHeight: 1.05, letterSpacing: wmSize * 0.16, paddingLeft: wmSize * 0.16, whiteSpace: 'nowrap' }}>
          {[...`3D ${word}`].map((ch, i, all) => {
            const k = interpolate(bf, [24 + i * 2, 36 + i * 2], [0, 1], clamp);
            // golden light sweep: letters near the moving highlight turn white-hot
            const pos = (i + 0.5) / all.length * 100;
            const hot = Math.max(0, 1 - Math.abs(pos - sweep) / 16);
            const mix = (a: number, b: number) => Math.round(a + (b - a) * hot);
            const color = `rgb(${mix(240, 255)}, ${mix(214, 252)}, ${mix(158, 240)})`;
            return <span key={i} style={{ display: 'inline-block', color, opacity: k, transform: `translateY(${(1 - k) * wmSize * 0.25}px)`, filter: `blur(${(1 - k) * 8}px)`, textShadow: `0 6px 22px rgba(0,0,0,0.6), 0 0 ${wmSize * 0.5 * hot}px rgba(255,214,140,${0.9 * hot})`, whiteSpace: 'pre' }}>{ch}</span>;
          })}
        </div>
        <div style={{ fontFamily: SERIF, fontWeight: 600, fontSize: u * (portrait ? 0.04 : 0.036), letterSpacing: u * 0.008, color: '#e9d4a6', marginTop: u * 0.03, opacity: tag, transform: `translateY(${(1 - tag) * 14}px)` }}>
          Your Move. Your Victory.
        </div>
        <div style={{ marginTop: u * (portrait ? 0.07 : 0.055), display: 'flex', justifyContent: 'center', opacity: Math.min(1, btn * 1.4), transform: `scale(${0.8 + 0.2 * btn})` }}>
          <div style={{ padding: `${u * 0.022}px ${u * 0.075}px`, borderRadius: u * 0.05, background: 'linear-gradient(180deg, #f6d894, #dfae55)', color: '#1a1208', fontFamily: SANS, fontWeight: 800, fontSize: u * 0.04, letterSpacing: u * 0.008, boxShadow: `0 0 ${u * (0.03 + 0.03 * glow)}px rgba(243,208,138,${0.35 + 0.3 * glow}), 0 10px 30px rgba(0,0,0,0.5)` }}>
            PLAY NOW
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
