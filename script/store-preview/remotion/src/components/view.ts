// A camera is a View: the native pixel (cx, cy) of the capture world sits at the centre of the stage,
// magnified by s (screen px per native px). Keyframes interpolate centre linearly and scale geometrically.
import {interpolate} from 'remotion';
import {ease, stage} from '../theme/tokens';

export type View = {cx: number; cy: number; s: number};
export type Key = View & {at: number};
export type Rect = {x: number; y: number; w: number; h: number};

/** Never magnify a capture past its own pixels: 1 native pixel = 1 output pixel at most. */
export const MAX_SCALE = 1;

/** The view that puts native point (px, py) at screen point (sx, sy) at scale s. */
export const anchor = (px: number, py: number, sx: number, sy: number, s: number): View => ({
  cx: px - (sx - stage.cx) / s,
  cy: py - (sy - stage.cy) / s,
  s: Math.min(s, MAX_SCALE),
});

export const viewAt = (frame: number, keys: Key[]): View => {
  if (frame <= keys[0].at) return keys[0];
  for (let i = 0; i < keys.length - 1; i++) {
    const a = keys[i];
    const b = keys[i + 1];
    if (frame <= b.at) {
      const p = interpolate(frame, [a.at, b.at], [0, 1], {easing: ease.camera});
      return {
        cx: a.cx + (b.cx - a.cx) * p,
        cy: a.cy + (b.cy - a.cy) * p,
        s: Math.exp(Math.log(a.s) + (Math.log(b.s) - Math.log(a.s)) * p),
      };
    }
  }
  return keys[keys.length - 1];
};

/** Screen position of the world origin for a view. */
export const origin = (v: View) => ({x: stage.cx - v.cx * v.s, y: stage.cy - v.cy * v.s});
