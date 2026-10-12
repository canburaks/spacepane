import React from 'react';
import {AbsoluteFill, staticFile, useCurrentFrame} from 'remotion';
import {color} from '../theme/tokens';
import {TOTAL_FRAMES} from '../theme/timing';

// The approved screenshots use a vivid indigo -> violet -> magenta -> amber blend at 135 degrees.
// Here it drifts slowly (angle and stops move a few percent over the whole video) and carries a soft
// light from above. A static noise tile at ~3% dithers it so H.264 does not band.
export const Background: React.FC = () => {
  const frame = useCurrentFrame();
  const t = (frame / TOTAL_FRAMES) * Math.PI * 2;
  const angle = 132 + Math.sin(t) * 9;
  const shift = Math.sin(t + 1.1) * 4;
  const lx = 50 + Math.sin(t * 1.0 + 0.4) * 14;
  const ly = -8 + Math.cos(t) * 4;
  return (
    <AbsoluteFill style={{background: color.night}}>
      <AbsoluteFill
        style={{
          background: `linear-gradient(${angle}deg, ${color.brand} ${0 + shift}%, ${color.violet} ${36 + shift}%, ${color.magenta} ${70 + shift}%, ${color.amber} ${104 + shift}%)`,
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(ellipse 70% 55% at ${lx}% ${ly}%, rgba(255,255,255,0.20), rgba(255,255,255,0) 70%)`,
        }}
      />
      <AbsoluteFill
        style={{background: 'radial-gradient(ellipse 120% 100% at 50% 40%, rgba(7,8,26,0) 55%, rgba(7,8,26,0.26) 100%)'}}
      />
      <AbsoluteFill
        style={{backgroundImage: `url(${staticFile('noise.png')})`, backgroundSize: '256px 256px', opacity: 0.045, mixBlendMode: 'overlay'}}
      />
    </AbsoluteFill>
  );
};
