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

const dur = sceneDurations.database;
const table = captures.sqliteTable;
const summary = captures.sqliteSummary;
const base = anchor(table.w / 2, 0, 960, 300, 1600 / table.w);
const detail = anchor(20, 230, 110, 340, 1);
const detailEnd = detail; // hold still: a slow sub-pixel drift makes small text swim
const keys: Key[] = [
  {at: 0, ...base},
  {at: 12, ...base},
  {at: 46, ...detail},
  {at: 74, ...detail},
  {at: dur, ...detailEnd},
];

// "Source read only: Yes" on the Summary view, native pixels.
const holes = [{x: 56, y: 372, w: 640, h: 46}];

export const DatabaseScene: React.FC = () => {
  const frame = useCurrentFrame();
  const view = viewAt(frame, keys);
  const swap = interpolate(frame, [58, 72], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.inOut});
  const p = interpolate(frame, [78, 94], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.soft});
  return (
    <>
      <Stage id="database">
        <Camera view={view}>
          <Win capture={table} />
          <Win capture={summary} opacity={swap}>
            <Spotlight id="db" w={summary.w} h={summary.h} holes={holes} progress={p} viewScale={view.s} />
          </Win>
        </Camera>
      </Stage>
      <Header eyebrow="SQLite" headline="A database at a glance. *Read-only.*" end={dur - 14} />
    </>
  );
};
