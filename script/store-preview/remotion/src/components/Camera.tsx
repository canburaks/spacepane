import React from 'react';
import {origin, type View} from './view';

/** Positions its children (in native capture pixels) through a View. */
export const Camera: React.FC<{view: View; children: React.ReactNode}> = ({view, children}) => {
  const o = origin(view);
  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        transformOrigin: '0 0',
        transform: `translate3d(${o.x}px, ${o.y}px, 0) scale(${view.s})`,
        willChange: 'transform',
      }}
    >
      {children}
    </div>
  );
};
