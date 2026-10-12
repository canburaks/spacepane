import React from 'react';
import {useCurrentFrame} from 'remotion';
import {color, layout} from '../theme/tokens';
import type {Rect} from './view';

/**
 * A staging overlay drawn in native capture pixels: dims the capture outside the given rectangles and
 * rings them. It adds no UI of its own; `progress` runs 0..1.
 */
export const Spotlight: React.FC<{w: number; h: number; holes: Rect[]; progress: number; viewScale: number; id: string; dim?: number}> = ({w, h, holes, progress, viewScale, id, dim = 0.62}) => {
  const frame = useCurrentFrame();
  if (progress <= 0) return null;
  const pulse = 0.78 + 0.22 * Math.sin(frame / 5);
  return (
    <svg width={w} height={h} style={{position: 'absolute', left: 0, top: 0}}>
      <defs>
        <mask id={`mask-${id}`}>
          <rect width={w} height={h} fill="white" />
          {holes.map((r, i) => (
            <rect key={i} x={r.x} y={r.y} width={r.w} height={r.h} rx={14} fill="black" />
          ))}
        </mask>
        <clipPath id={`clip-${id}`}>
          <rect width={w} height={h} rx={layout.windowRadius} />
        </clipPath>
      </defs>
      <g clipPath={`url(#clip-${id})`}>
        <rect width={w} height={h} fill={color.night} opacity={dim * progress} mask={`url(#mask-${id})`} />
      </g>
      {holes.map((r, i) => (
        <rect
          key={i}
          x={r.x}
          y={r.y}
          width={r.w}
          height={r.h}
          rx={14}
          fill="none"
          stroke={color.amber}
          strokeWidth={3.5 / viewScale}
          opacity={progress * pulse}
        />
      ))}
    </svg>
  );
};
