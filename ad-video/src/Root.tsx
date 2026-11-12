import React from 'react';
import { Composition } from 'remotion';
import { Ad } from './Ad';
import { TOTAL_FRAMES } from './scenes';
import { FPS } from './timeline';

export const Root: React.FC = () => (
  <>
    <Composition id="AdVertical" component={Ad} durationInFrames={TOTAL_FRAMES} fps={FPS} width={1080} height={1920} />
    <Composition id="AdLandscape" component={Ad} durationInFrames={TOTAL_FRAMES} fps={FPS} width={1920} height={1080} />
  </>
);
