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

const dur = sceneDurations.notebook;
const cap = captures.notebook;
const base = anchor(cap.w / 2, 0, 960, 300, 1600 / cap.w);
const detail = anchor(760, 430, 330, 290, 0.9);
const detailEnd = detail; // hold still: a slow sub-pixel drift makes small text swim
const keys: Key[] = [
  {at: 0, ...base},
  {at: 8, ...base},
  {at: 38, ...detail},
  {at: dur, ...detailEnd},
];

// Code cell [1] and its saved Output, native pixels.
const holes = [{x: 1010, y: 685, w: 965, h: 460}];

export const NotebookScene: React.FC = () => {
  const frame = useCurrentFrame();
  const view = viewAt(frame, keys);
  const p = interpolate(frame, [46, 62], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.soft});
  return (
    <>
      <Stage id="notebook">
        <Camera view={view}>
          <Win capture={cap}>
            <Spotlight id="notebook" w={cap.w} h={cap.h} holes={holes} progress={p} viewScale={view.s} />
          </Win>
        </Camera>
      </Stage>
      <Header eyebrow="Jupyter" headline="Notebooks as saved. *Never run.*" end={dur - 14} />
    </>
  );
};
