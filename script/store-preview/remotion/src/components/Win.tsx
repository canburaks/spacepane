import React from 'react';
import {Img, staticFile} from 'remotion';
import type {Capture} from '../data/captures';
import {layout} from '../theme/tokens';

// A real window capture placed in world (native pixel) coordinates. The capture keeps its own transparent
// rounded corners; the shadow is drawn around the same radius.
export const Win: React.FC<{
  capture: Capture;
  x?: number;
  y?: number;
  opacity?: number;
  /** Extra transform (entry motion) applied about the window's centre, in native pixels. */
  dy?: number;
  scale?: number;
  children?: React.ReactNode;
}> = ({capture, x = 0, y = 0, opacity = 1, dy = 0, scale = 1, children}) => (
  <div
    style={{
      position: 'absolute',
      left: x,
      top: y,
      width: capture.w,
      height: capture.h,
      borderRadius: layout.windowRadius,
      opacity,
      transform: `translate3d(0, ${dy}px, 0) scale(${scale})`,
      transformOrigin: '50% 50%',
      boxShadow: '0 70px 170px rgba(6,3,28,0.50), 0 22px 60px rgba(6,3,28,0.32), 0 0 0 1px rgba(255,255,255,0.06)',
    }}
  >
    <div style={{position: 'absolute', inset: 0, borderRadius: layout.windowRadius, overflow: 'hidden'}}>
      <Img src={staticFile(capture.src)} style={{width: capture.w, height: capture.h, display: 'block'}} />
      {children}
    </div>
  </div>
);
