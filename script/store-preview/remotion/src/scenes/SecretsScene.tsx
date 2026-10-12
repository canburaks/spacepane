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

const dur = sceneDurations.secrets;
const cap = captures.source;
const base = anchor(cap.w / 2, 0, 960, 300, 1600 / cap.w);
const detail = anchor(20, 150, 280, 350, 1);
const detailEnd = detail; // hold still: a slow sub-pixel drift makes small text swim
const keys: Key[] = [
  {at: 0, ...base},
  {at: 22, ...base},
  {at: 62, ...detail},
  {at: dur, ...detailEnd},
];

// Native-pixel rectangles on the Source view: the findings banner and the two concealed values.
const holes = [
  {x: 28, y: 150, w: 862, h: 92},
  {x: 66, y: 672, w: 335, h: 48},
  {x: 66, y: 802, w: 235, h: 48},
];

export const SecretsScene: React.FC = () => {
  const frame = useCurrentFrame();
  const view = viewAt(frame, keys);
  const p = interpolate(frame, [58, 76], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.soft});
  return (
    <>
      <Stage id="secrets" enter="dissolve">
        <Camera view={view}>
          <Win capture={cap}>
            <Spotlight id="secrets" w={cap.w} h={cap.h} holes={holes} progress={p} viewScale={view.s} />
          </Win>
        </Camera>
      </Stage>
      <Header eyebrow="JSON" headline="Likely secrets *concealed*, and counted." end={dur - 14} />
    </>
  );
};
