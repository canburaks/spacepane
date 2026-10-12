import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {ease, layout, springs} from '../theme/tokens';
import {OVERLAP, sceneDurations, type SceneId} from '../theme/timing';

export type EnterMode = 'rise' | 'dissolve';
export type ExitMode = 'fall' | 'hold';

/**
 * The area below the header where captures live. Handles the scene's entry/exit motion and the soft mask
 * that lets captures slide under the headline without colliding with it.
 */
export const Stage: React.FC<{
  id: SceneId;
  enter?: EnterMode;
  exit?: ExitMode;
  /** Local frame at which entry begins. */
  delay?: number;
  /** Bottom of the header (screen px) for this scene; captures fade out above it. */
  headerBottom?: number;
  children: React.ReactNode;
}> = ({id, enter = 'rise', exit = 'fall', delay = 2, headerBottom = layout.headerBottom, children}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const dur = sceneDurations[id];

  let opacity = 1;
  let dy = 0;
  let scale = 1;
  if (enter === 'rise') {
    const p = spring({frame: frame - delay, fps, config: springs.ui});
    opacity = interpolate(p, [0, 0.5], [0, 1], {extrapolateRight: 'clamp', extrapolateLeft: 'clamp'});
    dy = (1 - p) * 140;
    scale = 0.965 + 0.035 * p;
  } else {
    opacity = interpolate(frame, [0, OVERLAP], [0, 1], {extrapolateRight: 'clamp'});
  }
  if (exit === 'fall') {
    const q = interpolate(frame, [dur - OVERLAP, dur], [0, 1], {extrapolateLeft: 'clamp', easing: ease.inOut});
    opacity *= 1 - q;
    dy += q * 44;
    scale *= 1 - 0.012 * q;
  }
  const maskStart = headerBottom;
  const maskEnd = headerBottom + 44;
  return (
    <AbsoluteFill
      style={{
        WebkitMaskImage: `linear-gradient(to bottom, transparent ${maskStart}px, #000 ${maskEnd}px)`,
        maskImage: `linear-gradient(to bottom, transparent ${maskStart}px, #000 ${maskEnd}px)`,
      }}
    >
      <AbsoluteFill style={{opacity, transform: `translate3d(0, ${dy}px, 0) scale(${scale})`, transformOrigin: '50% 75%'}}>
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
