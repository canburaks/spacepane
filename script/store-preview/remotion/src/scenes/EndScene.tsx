import React from 'react';
import {Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {color, ease, font, springs} from '../theme/tokens';

export const EndScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const icon = spring({frame: frame - 8, fps, config: springs.pop});
  const name = spring({frame: frame - 20, fps, config: springs.ui});
  const sub = spring({frame: frame - 30, fps, config: springs.ui});
  const glow = interpolate(frame, [8, 40], [0, 1], {extrapolateRight: 'clamp', easing: ease.soft});
  return (
    <div style={{position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 34}}>
      <div style={{position: 'relative', width: 300, height: 300, opacity: Math.min(1, icon * 1.5), transform: `scale(${0.6 + 0.4 * icon}) translate3d(0, ${(1 - icon) * 40}px, 0)`}}>
        <div
          style={{
            position: 'absolute',
            inset: -90,
            background: `radial-gradient(circle, rgba(166,77,255,${0.55 * glow}) 0%, rgba(166,77,255,0) 62%)`,
          }}
        />
        <Img src={staticFile('icon.svg')} style={{position: 'relative', width: 300, height: 300, display: 'block', filter: 'drop-shadow(0 30px 50px rgba(8,4,40,0.35))'}} />
      </div>
      <div
        style={{
          fontFamily: font.display,
          fontWeight: 600,
          fontSize: 96,
          letterSpacing: '-0.035em',
          color: color.white,
          textShadow: '0 4px 36px rgba(24,6,80,0.38)',
          opacity: Math.min(1, name * 1.5),
          transform: `translate3d(0, ${(1 - name) * 30}px, 0)`,
        }}
      >
        SpacePane <span style={{fontFamily: font.serif, fontStyle: 'italic', fontWeight: 500, letterSpacing: '-0.02em'}}>for Quick Look</span>
      </div>
      <div
        style={{
          fontFamily: font.text,
          fontWeight: 500,
          fontSize: 38,
          letterSpacing: '-0.01em',
          color: 'rgba(255,255,255,0.92)',
          opacity: Math.min(1, sub * 1.5),
          transform: `translate3d(0, ${(1 - sub) * 20}px, 0)`,
        }}
      >
        Preview JSON, SQLite, Markdown
      </div>
    </div>
  );
};
