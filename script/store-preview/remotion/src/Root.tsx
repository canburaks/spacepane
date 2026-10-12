import React from 'react';
import {Composition} from 'remotion';
import {Preview} from './Preview';
import {TOTAL_FRAMES} from './theme/timing';
import {FPS, HEIGHT, WIDTH} from './theme/tokens';

export const Root: React.FC = () => (
  <Composition id="SpacePanePreview" component={Preview} durationInFrames={TOTAL_FRAMES} fps={FPS} width={WIDTH} height={HEIGHT} />
);
