// Brand tokens from DESIGN.md in the spacepane-web repository and the layout constants shared by every scene.
import {Easing} from 'remotion';

export const color = {
  paper: '#f4f1ea',
  ink: '#0b0d1a',
  night: '#07081a',
  brand: '#4b3cff',
  violet: '#a64dff',
  magenta: '#ff4f9a',
  amber: '#ffb547',
  mint: '#4fe3c1',
  white: '#ffffff',
} as const;

// System fonts only, like the website. SF Pro Display weight 600 for headlines, New York italic as the accent.
export const font = {
  display: '-apple-system, "SF Pro Display", "Helvetica Neue", system-ui, sans-serif',
  text: '-apple-system, "SF Pro Text", "Helvetica Neue", system-ui, sans-serif',
  serif: '"New York", ui-serif, "Iowan Old Style", Georgia, serif',
  mono: 'ui-monospace, "SF Mono", Menlo, monospace',
} as const;

export {FPS} from './timing';
export const WIDTH = 1920;
export const HEIGHT = 1080;

// Easings (DESIGN.md in the spacepane-web repository: --ease-soft, --ease-glide) plus a symmetric curve for camera moves.
export const ease = {
  soft: Easing.bezier(0.22, 1, 0.36, 1),
  glide: Easing.bezier(0.2, 0.75, 0.2, 1),
  camera: Easing.bezier(0.45, 0, 0.2, 1),
  inOut: Easing.bezier(0.65, 0, 0.35, 1),
} as const;

// Spring presets (damping / stiffness / mass) used with remotion's spring().
export const springs = {
  // settles quickly with a tiny overshoot: headlines, windows
  ui: {damping: 22, stiffness: 150, mass: 0.9},
  // slightly bouncier: keycap, icon
  pop: {damping: 13, stiffness: 190, mass: 0.8},
  // no overshoot: camera-like settles
  calm: {damping: 30, stiffness: 120, mass: 1},
} as const;

// Layout. The header (eyebrow + headline) lives above HEADER_BOTTOM; the stage below it is where captures live.
export const layout = {
  headerTop: 50,
  headerBottom: 236,
  stageTop: 262,
  stageBottom: 1050,
  sideMargin: 60,
  // native-pixel radius of the captured macOS windows
  windowRadius: 50,
} as const;

export const stage = {
  x: layout.sideMargin,
  y: layout.stageTop,
  w: WIDTH - layout.sideMargin * 2,
  h: layout.stageBottom - layout.stageTop,
  cx: WIDTH / 2,
  cy: (layout.stageTop + layout.stageBottom) / 2,
} as const;
