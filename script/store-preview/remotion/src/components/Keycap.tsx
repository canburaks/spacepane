import React from 'react';
import {interpolate, useCurrentFrame} from 'remotion';
import {ease, font} from '../theme/tokens';

/** 0 = resting, 1 = fully pressed, for a press that starts at local frame f0. */
export const pressProgress = (frame: number, f0: number): number => {
  const down = interpolate(frame, [f0, f0 + 4], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.soft});
  const up = interpolate(frame, [f0 + 9, f0 + 18], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.soft});
  return down * (1 - up);
};

// The space bar from the app icon, as a keycap: pale face, darker edge, a slight travel when pressed.
export const Keycap: React.FC<{width: number; height?: number; press: number; label?: string}> = ({width, height = Math.round(width * 0.23), press, label = 'space'}) => {
  const travel = height * 0.09;
  return (
    <div style={{position: 'relative', width, height: height + travel}}>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: travel,
          height,
          borderRadius: height * 0.24,
          background: 'linear-gradient(180deg, #b7c0d3, #8f99b0)',
          boxShadow: `0 ${height * 0.3}px ${height * 0.6}px rgba(12,6,50,${0.42 - press * 0.12})`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: press * travel,
          height,
          borderRadius: height * 0.24,
          background: 'linear-gradient(180deg, #ffffff 0%, #eef1f8 55%, #dde3ef 100%)',
          boxShadow: `inset 0 ${height * 0.02}px 0 rgba(255,255,255,0.95), inset 0 -${height * 0.04}px ${height * 0.08}px rgba(110,120,155,0.28)`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontFamily: font.text,
          fontWeight: 600,
          fontSize: height * 0.26,
          letterSpacing: '0.05em',
          color: '#5b6074',
        }}
      >
        {label}
      </div>
    </div>
  );
};

export const KeyRipple: React.FC<{f0: number; size: number}> = ({f0, size}) => {
  const frame = useCurrentFrame();
  const p = interpolate(frame, [f0 + 3, f0 + 26], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.soft});
  if (p <= 0 || p >= 1) return null;
  return (
    <div
      style={{
        position: 'absolute',
        left: '50%',
        top: '50%',
        width: size,
        height: size * 0.3,
        marginLeft: -size / 2,
        marginTop: -size * 0.15,
        borderRadius: size * 0.08,
        border: '3px solid rgba(255,255,255,0.7)',
        opacity: (1 - p) * 0.7,
        transform: `scale(${1 + p * 0.45})`,
      }}
    />
  );
};
