import React from 'react';
import {interpolate, useCurrentFrame} from 'remotion';
import {Camera} from '../components/Camera';
import {anchor, viewAt, type Key} from '../components/view';
import {Header} from '../components/Header';
import {Stage} from '../components/Stage';
import {Win} from '../components/Win';
import {captures} from '../data/captures';
import {sceneDurations} from '../theme/timing';
import {ease} from '../theme/tokens';

// The companion app: File Types, then (the same window, the sidebar selection moving) Theme.
const dur = sceneDurations.settings;
const fileTypes = captures.fileTypes;
const theme = captures.theme;
const SWAP = 56; // frame at which File Types dissolves into Theme

const base = anchor(fileTypes.w / 2, 0, 960, 300, 1600 / fileTypes.w);
const detail = anchor(1290, 0, 960, 296, 0.74);
const detailEnd = detail; // hold still: a slow sub-pixel drift makes small text swim
const keys: Key[] = [
  {at: 0, ...base},
  {at: 8, ...base},
  {at: 38, ...detail},
  {at: dur, ...detailEnd},
];

export const SettingsScene: React.FC = () => {
  const frame = useCurrentFrame();
  const view = viewAt(frame, keys);
  const swap = interpolate(frame, [SWAP, SWAP + 12], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.inOut});
  return (
    <>
      <Stage id="settings">
        <Camera view={view}>
          <Win capture={fileTypes} />
          <Win capture={theme} opacity={swap} />
        </Camera>
      </Stage>
      <Header eyebrow="File Types" headline="A switch for *every file type.*" start={6} end={SWAP - 8} />
      <Header eyebrow="Theme" headline="Your colors. *Your type.*" start={SWAP + 8} end={dur - 14} />
    </>
  );
};
