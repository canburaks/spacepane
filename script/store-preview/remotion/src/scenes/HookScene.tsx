import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {Camera} from '../components/Camera';
import {anchor, viewAt, type Key} from '../components/view';
import {Headline} from '../components/Header';
import {Keycap, KeyRipple, pressProgress} from '../components/Keycap';
import {Stage} from '../components/Stage';
import {Win} from '../components/Win';
import {captures, panelOverFinder} from '../data/captures';
import {HOOK_PRESS_FRAME, sceneDurations} from '../theme/timing';
import {ease, layout, springs, WIDTH} from '../theme/tokens';

const dur = sceneDurations.hook;
const MOVE = 46; // frame at which the headline leaves hero size and the windows rise

const composite = anchor(1310, 0, 960, 330, 0.64);
// Panel-aligned view; the Source scene starts from exactly this framing so the two dissolve cleanly.
const panel = anchor(panelOverFinder.x, panelOverFinder.y, 160, 300, 1600 / captures.outline.w);
const keys: Key[] = [
  {at: 0, ...composite},
  {at: 70, ...composite},
  {at: 122, ...panel},
  {at: dur, ...panel},
];

export const HookScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const press = pressProgress(frame, HOOK_PRESS_FRAME);
  const move = spring({frame: frame - MOVE, fps, config: springs.ui});
  const keyIn = spring({frame: frame - 3, fps, config: springs.pop});
  const keyOut = interpolate(frame, [MOVE - 10, MOVE], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.inOut});
  const heroScale = 1 + (1 - move) * 1.1;
  const heroDy = (1 - move) * 280;
  const view = viewAt(frame, keys);
  const panelP = spring({frame: frame - (MOVE + 12), fps, config: springs.ui});
  const finderOpacity = interpolate(frame, [64, 100], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.inOut});
  const headerEnd = dur - 14;
  const keyWidth = 700;

  return (
    <>
      <Stage id="hook" delay={MOVE} exit="hold">
        <Camera view={view}>
          <Win capture={captures.finder} opacity={finderOpacity} />
          <Win
            capture={captures.outline}
            x={panelOverFinder.x}
            y={panelOverFinder.y}
            opacity={interpolate(panelP, [0, 0.4], [0, 1], {extrapolateRight: 'clamp'})}
            dy={(1 - panelP) * 70}
            scale={0.95 + 0.05 * panelP}
          />
        </Camera>
      </Stage>

      <div style={{position: 'absolute', left: 0, right: 0, top: layout.headerTop, transform: `translate3d(0, ${heroDy}px, 0) scale(${heroScale})`, transformOrigin: '50% 0'}}>
        <Headline text="Press Space." size={72} start={1} end={headerEnd} />
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: layout.headerTop + 78}}>
        <Headline text="See *what's really inside.*" size={72} start={MOVE + 6} end={headerEnd} />
      </div>

      <div
        style={{
          position: 'absolute',
          left: (WIDTH - keyWidth) / 2,
          top: 590,
          opacity: Math.min(1, keyIn * 1.4) * (1 - keyOut),
          transform: `translate3d(0, ${(1 - keyIn) * 40 + keyOut * 70}px, 0) scale(${(0.7 + 0.3 * keyIn) * (1 - keyOut * 0.18)})`,
        }}
      >
        <KeyRipple f0={HOOK_PRESS_FRAME} size={keyWidth} />
        <Keycap width={keyWidth} press={press} />
      </div>
    </>
  );
};
