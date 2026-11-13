// THE FINAL MOVE: 27 s, 30 fps. Scene map and timing live in scenes.ts.
import React, { useCallback } from 'react';
import { AbsoluteFill, interpolate, Sequence, useCurrentFrame } from 'remotion';
import { AudioTrack } from './AudioTrack';
import { Brand } from './Brand';
import { cameraAt } from './camera';
import './fonts';
import { useLayout } from './layout';
import { CheckmateText, HookText, LightSweep, Vignette } from './Overlays';
import { PhoneScene } from './Phone';
import { MATE_FRAME, mainScene, shots, T } from './scenes';
import { moodAt, Stage } from './Stage';
import { PieceState } from './timeline';

const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;

const Cinematic: React.FC = () => {
  const { portrait } = useLayout();
  const camAt = useCallback((f: number, p: PieceState[]) => cameraAt(shots, f, portrait, p), [portrait]);
  const mood = useCallback((f: number) => moodAt(f, MATE_FRAME), []);
  return (
    <AbsoluteFill style={{ background: '#0a0806' }}>
      <Stage scene={mainScene} camAt={camAt} moodAt={mood} />
      <Vignette />
      <Sequence from={0} durationInFrames={96} layout="none"><HookText /></Sequence>
      <CheckmateText at={MATE_FRAME + 3} out={498} />
      <LightSweep from={494} to={526} />
    </AbsoluteFill>
  );
};

export const Ad: React.FC = () => (
  <AbsoluteFill style={{ background: '#070504' }}>
    <Sequence from={0} durationInFrames={T.phone + 20}>
      <FadeOut start={T.phone + 2} end={T.phone + 18}><Cinematic /></FadeOut>
    </Sequence>
    <Sequence from={T.phone - 5} durationInFrames={T.brand + 12 - (T.phone - 5)}><PhoneScene /></Sequence>
    <Sequence from={T.brand - 4} durationInFrames={T.end - (T.brand - 4)}><Brand /></Sequence>
    <AudioTrack />
  </AbsoluteFill>
);

const FadeOut: React.FC<{ start: number; end: number; children: React.ReactNode }> = ({ start, end, children }) => {
  // frame inside this sequence equals the film frame (the sequence starts at 0)
  const f = useCurrentFrame();
  return <AbsoluteFill style={{ opacity: interpolate(f, [start, end], [1, 0], clamp) }}>{children}</AbsoluteFill>;
};
