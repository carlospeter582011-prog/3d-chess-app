// Sound design placement. Every cue is positioned on the film timeline in frames, so sound stays locked to the picture.
// All files are original (synthesised by scripts/synth-audio.mjs).
import React from 'react';
import { Audio, Sequence, staticFile } from 'remotion';
import { MATE_FRAME, mainScene, T } from './scenes';

type Cue = { f: number; file: string; vol: number };

const cues: Cue[] = [
  { f: 0, file: 'hit_intro', vol: 0.5 },
  // whooshes on every cut, so the edit feels driven by the sound
  ...[92, 150, 186, 222, 244, 272].map((f) => ({ f, file: 'whoosh', vol: 0.42 })),
  { f: 295, file: 'whoosh', vol: 0.5 },
  { f: 332, file: 'whoosh', vol: 0.4 },
  { f: 338, file: 'riser', vol: 0.5 },
  { f: MATE_FRAME, file: 'impact', vol: 1.0 },
  { f: 498, file: 'swish', vol: 0.6 },
  ...[512, 566, 614, 658].map((f) => ({ f, file: 'tick', vol: 0.45 })),
  { f: T.brand - 8, file: 'swish', vol: 0.45 },
  { f: T.brand + 36, file: 'brand', vol: 0.75 },
  { f: T.brand + 80, file: 'tick', vol: 0.5 },
  // piece sounds come from the timeline itself: they play when each piece lands
  ...mainScene.sounds.map((s) => ({ f: s.frame, file: s.name === 'impact' ? '' : s.name, vol: s.name === 'capture' ? 0.95 : s.name.startsWith('fall') ? 0.9 : 0.8 })),
].filter((c) => c.file !== '');

export const AudioTrack: React.FC = () => (
  <>
    <Audio src={staticFile('sfx/music.wav')} volume={0.4} />
    {cues.map((c, i) => (
      <Sequence key={i} from={c.f} layout="none">
        <Audio src={staticFile(`sfx/${c.file}.wav`)} volume={c.vol} />
      </Sequence>
    ))}
  </>
);
