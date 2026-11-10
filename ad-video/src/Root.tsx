import React from 'react';
import { Composition } from 'remotion';
import { Ad, AD_FRAMES } from './Ad';
import { FPS } from './timeline';

export const Root: React.FC = () => (
  <>
    <Composition id="AdVertical" component={Ad} durationInFrames={AD_FRAMES} fps={FPS} width={1080} height={1920} />
    <Composition id="AdLandscape" component={Ad} durationInFrames={AD_FRAMES} fps={FPS} width={1920} height={1080} />
  </>
);
