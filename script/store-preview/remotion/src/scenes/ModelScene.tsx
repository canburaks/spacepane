import React from 'react';
import {useCurrentFrame} from 'remotion';
import {Camera} from '../components/Camera';
import {anchor, viewAt, type Key} from '../components/view';
import {Header} from '../components/Header';
import {Stage} from '../components/Stage';
import {Win} from '../components/Win';
import {captures} from '../data/captures';
import {sceneDurations} from '../theme/timing';

const dur = sceneDurations.model;
const cap = captures.model;
const base = anchor(cap.w / 2, 0, 960, 330, 0.62);
const detail = anchor(1290, 480, 960, 548, 0.9);
const detailEnd = detail; // hold still: a slow sub-pixel drift makes small text swim
const keys: Key[] = [
  {at: 0, ...base},
  {at: 24, ...base},
  {at: 56, ...detail},
  {at: dur, ...detailEnd},
];

export const ModelScene: React.FC = () => {
  const frame = useCurrentFrame();
  const view = viewAt(frame, keys);
  return (
    <>
      <Stage id="model" headerBottom={262}>
        <Camera view={view}>
          <Win capture={cap} />
        </Camera>
      </Stage>
      <Header
        eyebrow="STEP · 3D"
        headline="Models you can *turn.*"
        note="STEP and IGES are off until you switch them on."
        end={dur - 14}
      />
    </>
  );
};
