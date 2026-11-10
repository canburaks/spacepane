// The real captures (copied by `npm run assets`) and their native pixel sizes. Nothing here is drawn or retouched.
export type Capture = {src: string; w: number; h: number};

const cap = (name: string, w: number, h: number): Capture => ({src: `captures/${name}.png`, w, h});

export const captures = {
  finder: cap('1-finder', 2000, 1240),
  outline: cap('1-panel', 2080, 1440),
  source: cap('2-panel', 2580, 1560),
  notebook: cap('3-panel', 2580, 1560),
  sqliteSummary: cap('4-panel-summary', 2580, 1560),
  sqliteTable: cap('4-panel-table', 2580, 1560),
  archive: cap('5-panel', 2580, 1560),
  markdown: cap('6-panel', 2580, 1560),
  fileTypes: cap('8-app', 2580, 1640),
  theme: cap('9-app', 2580, 1640),
} as const;

// Quick Look panel placement over the Finder window, from .build/store-screenshots/raw/geometry.tsv
// (points: finder at 60,80; panel at 330,150; 2 px per point).
export const panelOverFinder = {x: (330 - 60) * 2, y: (150 - 80) * 2};
