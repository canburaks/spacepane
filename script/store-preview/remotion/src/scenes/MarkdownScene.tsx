import React from 'react';
import {useCurrentFrame} from 'remotion';
import {Camera} from '../components/Camera';
import {anchor, viewAt, type Key} from '../components/view';
import {Header} from '../components/Header';
import {Stage} from '../components/Stage';
import {Win} from '../components/Win';
import {captures} from '../data/captures';
import {sceneDurations} from '../theme/timing';

const dur = sceneDurations.markdown;
const cap = captures.markdown;
const base = anchor(cap.w / 2, 0, 960, 300, 1600 / cap.w);
const detail = anchor(780, 215, 330, 330, 0.9);
const detailEnd = anchor(780, 540, 330, 330, 0.9);
const keys: Key[] = [
  {at: 0, ...base},
  {at: 8, ...base},
  {at: 34, ...detail},
  {at: dur, ...detailEnd},
];

export const MarkdownScene: React.FC = () => {
  const frame = useCurrentFrame();
  const view = viewAt(frame, keys);
  return (
    <>
      <Stage id="markdown">
        <Camera view={view}>
          <Win capture={cap} />
        </Camera>
      </Stage>
      <Header eyebrow="Markdown" headline="Markdown, *ready to read.*" end={dur - 14} />
    </>
  );
};
