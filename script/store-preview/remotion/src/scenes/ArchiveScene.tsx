import React from 'react';
import {interpolate, useCurrentFrame} from 'remotion';
import {Camera} from '../components/Camera';
import {anchor, viewAt, type Key} from '../components/view';
import {Header} from '../components/Header';
import {Spotlight} from '../components/Spotlight';
import {Stage} from '../components/Stage';
import {Win} from '../components/Win';
import {captures} from '../data/captures';
import {sceneDurations} from '../theme/timing';
import {ease} from '../theme/tokens';

const dur = sceneDurations.archive;
const cap = captures.archive;
const base = anchor(cap.w / 2, 0, 960, 300, 1600 / cap.w);
const detail = anchor(1290, 100, 960, 300, 0.74);
const detailEnd = detail; // hold still: a slow sub-pixel drift makes small text swim
const keys: Key[] = [
  {at: 0, ...base},
  {at: 8, ...base},
  {at: 40, ...detail},
  {at: dur, ...detailEnd},
];

// The listing summary: "Listed files: 14 . Listed folders: 6".
const holes = [{x: 28, y: 96, w: 690, h: 42}];

export const ArchiveScene: React.FC = () => {
  const frame = useCurrentFrame();
  const view = viewAt(frame, keys);
  const p = interpolate(frame, [48, 64], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.soft});
  return (
    <>
      <Stage id="archive">
        <Camera view={view}>
          <Win capture={cap}>
            <Spotlight id="archive" w={cap.w} h={cap.h} holes={holes} progress={p} viewScale={view.s} dim={0} />
          </Win>
        </Camera>
      </Stage>
      <Header eyebrow="ZIP" headline="Look inside. *Nothing is extracted.*" end={dur - 14} />
    </>
  );
};
