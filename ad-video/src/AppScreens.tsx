// The app's real screens, recreated in HTML/CSS from the verified Flutter source (lib/ui/menu.dart, hud.dart, theme.dart):
// same colours, copy text, layout order and controls. Only the glyph icons are redrawn as vector shapes (the app uses emoji,
// which depend on system fonts). The 3D board inside the game screen is the app's real GLB scene rendered by Stage.
// Screens are authored at the logical size of a phone, 390 x 844 CSS px.
import React, { useCallback } from 'react';
import { Img, interpolate, staticFile } from 'remotion';
import { Cam } from './camera';
import { SANS } from './fonts';
import { LightMood, Stage } from './Stage';
import { phoneScene } from './scenes';
import { PieceState } from './timeline';

export const SCREEN_W = 390;
export const SCREEN_H = 844;

const C = { bg: '#14100D', panel: 'rgba(26,20,15,0.84)', panelSolid: '#1D1610', line: 'rgba(255,226,170,0.14)', gold: '#E3B45E', gold2: '#F3D08A', text: '#F4EAD8', muted: '#A99B83', onGold: '#1A1208' };
const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;
const ease = (k: number) => k * k * (3 - 2 * k);

// ------------------------------------------------------------------ vector icons (24x24 box)
const Svg: React.FC<{ size?: number; color?: string; children: React.ReactNode }> = ({ size = 18, color = 'currentColor', children }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">{children}</svg>
);
const IconBot: React.FC<{ size?: number }> = ({ size }) => (
  <Svg size={size}><rect x="4" y="8" width="16" height="11" rx="3" /><path d="M12 8V4M9 13h.01M15 13h.01M9 16h6" /><circle cx="12" cy="3.5" r="1" /></Svg>
);
const IconPeople: React.FC<{ size?: number }> = ({ size }) => (
  <Svg size={size}><circle cx="9" cy="8" r="3" /><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6" /><circle cx="17" cy="9" r="2.4" /><path d="M16 14.2c3 0 5 2 5 5" /></Svg>
);
const IconSignal: React.FC<{ size?: number }> = ({ size }) => (
  <Svg size={size}><path d="M5 12a10 10 0 0 1 14 0M8 15a6 6 0 0 1 8 0" /><circle cx="12" cy="18.5" r="1.2" /></Svg>
);
const IconMenu = () => <Svg><path d="M4 7h16M4 12h16M4 17h16" /></Svg>;
const IconGear = () => <Svg><circle cx="12" cy="12" r="3" /><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M19.1 4.9L17 7M7 17l-2.1 2.1" /></Svg>;
const IconUndo = () => <Svg><path d="M9 7L4 12l5 5M4 12h10a6 6 0 0 1 0 12" transform="translate(0 -3)" /></Svg>;
const IconFlip = () => <Svg><path d="M20 12a8 8 0 1 1-2.4-5.7M20 4v5h-5" /></Svg>;
const IconTop = () => <Svg><rect x="4" y="4" width="16" height="16" rx="2" /><path d="M4 12h16M12 4v16" /></Svg>;
const IconReset = () => <Svg><circle cx="12" cy="12" r="8" /><circle cx="12" cy="12" r="2.5" /></Svg>;
const IconFlag = () => <Svg><path d="M6 21V4M6 4h11l-2.5 4L17 12H6" /></Svg>;

// ------------------------------------------------------------------ menu
const Heading: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ color: C.muted, fontSize: 12.5, letterSpacing: 0.9, textTransform: 'uppercase', fontWeight: 600 }}>{children}</div>
);

const Seg: React.FC<{ items: { label: React.ReactNode }[]; value: number; small?: boolean }> = ({ items, value, small }) => (
  <div style={{ position: 'relative', display: 'flex', padding: 4, background: '#17110E', borderRadius: 14, border: '1px solid #70583E' }}>
    <div style={{ position: 'absolute', top: 4, bottom: 4, left: 4, width: `calc((100% - 8px) / ${items.length})`, transform: `translateX(${value * 100}%)`, background: '#F2C977', border: '1px solid #FFE4A6', borderRadius: 10 }} />
    {items.map((it, i) => (
      <div key={i} style={{ position: 'relative', flex: 1, padding: `${small ? 11 : 13}px 3px`, textAlign: 'center', fontSize: small ? 13 : 12.5, fontWeight: 600, lineHeight: 1.2, color: Math.round(value) === i ? C.onGold : C.text, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
        {it.label}
      </div>
    ))}
  </div>
);

const PRESETS = [400, 800, 1200, 1600, 2000, 2400, 2800, 3200];

export const MenuScreen: React.FC<{ lf: number }> = ({ lf }) => {
  const modeIdx = interpolate(lf, [56, 64], [0, 1], clamp);
  const isBot = modeIdx < 0.5;
  const elo = Math.round(interpolate(lf, [6, 46], [1200, 2400], { ...clamp, easing: ease }) / 50) * 50;
  const pct = (elo - 400) / 2800;
  const press = interpolate(lf, [90, 94, 100], [0, 1, 0], clamp);
  return (
    <div style={{ position: 'absolute', inset: 0, background: `radial-gradient(ellipse at 50% 30%, rgba(20,16,13,0.35), #0A0806 85%), ${C.bg}`, fontFamily: SANS, color: C.text }}>
      <div style={{ position: 'absolute', left: 16, right: 16, top: '50%', transform: 'translateY(-50%)', padding: 20, background: C.panel, border: `1px solid ${C.line}`, borderRadius: 22, boxShadow: '0 20px 60px rgba(0,0,0,0.5)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <Img src={staticFile('icon.png')} style={{ width: 64, height: 64, borderRadius: 16 }} />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 28, color: C.gold2, letterSpacing: 0.3, lineHeight: 1.1 }}>3D Chess</div>
            <div style={{ fontSize: 13, color: C.muted, marginTop: 2 }}>Staunton set · works offline</div>
          </div>
          <div style={{ width: 40, height: 40, borderRadius: 12, border: `1px solid ${C.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: C.text }}><IconGear /></div>
        </div>
        <div style={{ height: 16 }} />
        <Seg value={modeIdx} items={[{ label: <><IconBot size={18} />Play the bot</> }, { label: <><IconPeople size={18} />2 players<br />1 phone</> }, { label: <><IconSignal size={18} />2 players<br />2 phones</> }]} />
        <div style={{ height: 16 }} />
        {isBot ? (
          <>
            <Heading>Your colour</Heading>
            <div style={{ height: 8 }} />
            <Seg small value={0} items={[{ label: 'White' }, { label: 'Random' }, { label: 'Black' }]} />
            <div style={{ height: 16 }} />
            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
              <Heading>Bot strength</Heading>
              <div style={{ color: C.gold2, fontSize: 16, fontWeight: 700 }}>{elo} Elo</div>
            </div>
            <div style={{ position: 'relative', height: 28, marginTop: 6 }}>
              <div style={{ position: 'absolute', left: 0, right: 0, top: 12, height: 4, borderRadius: 2, background: 'rgba(255,255,255,0.2)' }} />
              <div style={{ position: 'absolute', left: 0, width: `${pct * 100}%`, top: 12, height: 4, borderRadius: 2, background: C.gold }} />
              <div style={{ position: 'absolute', left: `calc(${pct * 100}% - 10px)`, top: 4, width: 20, height: 20, borderRadius: 10, background: C.gold, boxShadow: '0 2px 8px rgba(0,0,0,0.5)' }} />
            </div>
            <div style={{ display: 'flex', gap: 5, marginTop: 6 }}>
              {PRESETS.map((e) => {
                const on = Math.abs(elo - e) < 25;
                return <div key={e} style={{ flex: 1, textAlign: 'center', padding: '6px 0', fontSize: 12, borderRadius: 8, color: on ? C.gold2 : C.muted, border: `1px solid ${on ? C.gold : C.line}` }}>{e}</div>;
              })}
            </div>
            <div style={{ color: C.muted, fontSize: 12.5, marginTop: 10 }}>Stockfish runs on your device. Elo is approximate.</div>
          </>
        ) : (
          <div style={{ color: C.muted, fontSize: 14, lineHeight: 1.4 }}>Pass the phone or tablet back and forth — no internet needed. Turn on “Auto-flip board” in settings to turn the view 180° to the player whose turn it is.</div>
        )}
        <div style={{ height: 16 }} />
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Heading>Clock (optional)</Heading>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ color: C.gold2, fontSize: 14, fontWeight: 700 }}>Off</span>
            <div style={{ width: 44, height: 24, borderRadius: 12, background: '#3A2F25', position: 'relative' }}><div style={{ position: 'absolute', left: 3, top: 3, width: 18, height: 18, borderRadius: 9, background: '#fff' }} /></div>
          </div>
        </div>
        <div style={{ height: 16 }} />
        <div style={{ position: 'relative', textAlign: 'center', padding: '15px 0', borderRadius: 14, background: `linear-gradient(180deg, ${C.gold2}, ${C.gold})`, color: C.onGold, fontWeight: 700, fontSize: 16, transform: `scale(${1 - 0.03 * press})`, boxShadow: `0 0 ${24 * press}px rgba(243,208,138,${0.7 * press})` }}>
          ▶ Start new game
        </div>
      </div>
    </div>
  );
};

// ------------------------------------------------------------------ game screen
const HudButton: React.FC<{ icon: React.ReactNode; label: string; on?: boolean }> = ({ icon, label, on }) => (
  <div style={{ flex: 1, height: 42, borderRadius: 12, background: C.panel, border: `1px solid ${on ? C.gold : C.line}`, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 2, color: on ? C.gold2 : C.text }}>
    <div style={{ height: 17, display: 'flex', alignItems: 'center' }}>{icon}</div>
    <div style={{ fontSize: 9.5, color: C.muted, fontWeight: 500 }}>{label}</div>
  </div>
);

/** Camera of the phone's board: the app's orbit camera on a portrait screen. */
export function phoneCam(lf: number): (f: number, p: PieceState[]) => Cam {
  return () => {
    const orbit = ease(Math.min(1, Math.max(0, (lf - 112) / 40)));
    const top = ease(Math.min(1, Math.max(0, (lf - 152) / 24)));
    const th = (-58 * orbit * Math.PI) / 180;
    const ph = (((1 - top) * (46 - 6 * orbit) + top * 9) * Math.PI) / 180;
    const r = 16.8 * (1 - 0.05 * orbit);
    return { pos: [r * Math.sin(ph) * Math.sin(th), 0.4 + r * Math.cos(ph), r * Math.sin(ph) * Math.cos(th)], look: [0, 0.4, 0], fov: 60 };
  };
}
const phoneMood = (): LightMood => ({ key: 650, fill: 0.5, rim: 260, rimColor: '#ffc67a', hero: 0, red: 0, exposure: 1.0 });

export const GameScreen: React.FC<{ lf: number; fadeIn: number }> = ({ lf, fadeIn }) => {
  const bf = lf - 80;
  const landed = phoneScene.moves.filter((m) => bf >= m.start + m.dur).length;
  const turn = landed % 2 === 0 ? 'White' : 'Black';
  const camAt = useCallback((f: number, p: PieceState[]) => phoneCam(f + 80)(f, p), []);
  const topOn = lf >= 152;
  const tap = interpolate(lf, [146, 150, 158], [0, 1, 0], clamp);
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.bg, fontFamily: SANS, opacity: fadeIn, overflow: 'hidden' }}>
      <div style={{ position: 'absolute', left: 0, top: 0, width: SCREEN_W * 2, height: SCREEN_H * 2, transform: 'scale(0.5)', transformOrigin: 'top left' }}>
        <Stage scene={phoneScene} camAt={camAt} moodAt={phoneMood} frameOffset={-85} width={SCREEN_W * 2} height={SCREEN_H * 2} />
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, top: 54, display: 'flex', justifyContent: 'center' }}>
        <div style={{ padding: '6px 14px', borderRadius: 12, background: C.panel, border: `1px solid ${C.line}`, color: C.text, fontWeight: 600, fontSize: 13 }}>{turn} to move</div>
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 22, padding: '6px 6px', display: 'flex', gap: 4 }}>
        <HudButton icon={<IconMenu />} label="Menu" />
        <HudButton icon={<IconGear />} label="Settings" />
        <HudButton icon={<IconUndo />} label="Undo" />
        <HudButton icon={<IconFlip />} label="Flip" />
        <div style={{ flex: 1, display: 'flex', transform: `scale(${1 - 0.06 * tap})` }}><HudButton icon={<IconTop />} label="Top" on={topOn} /></div>
        <HudButton icon={<IconReset />} label="Reset" />
        <HudButton icon={<span style={{ fontSize: 15, fontWeight: 700 }}>½</span>} label="Draw" />
        <HudButton icon={<IconFlag />} label="Resign" />
      </div>
    </div>
  );
};
