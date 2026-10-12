// Every duration and scene start lives here (frames at 30 fps). Scenes overlap by OVERLAP frames.
export const FPS = 30;

export const OVERLAP = 12; // 0.4 s hand-off between scenes

export const sceneDurations = {
  hook: 150,
  secrets: 138,
  database: 114,
  archive: 96,
  notebook: 93,
  markdown: 87,
  model: 90,
  settings: 120,
  end: 78,
} as const;

export type SceneId = keyof typeof sceneDurations;
const order = Object.keys(sceneDurations) as SceneId[];

export const sceneStart = (id: SceneId): number => {
  let t = 0;
  for (const key of order) {
    if (key === id) return t;
    t += sceneDurations[key] - OVERLAP;
  }
  return t;
};

export const TOTAL_FRAMES = order.reduce((sum, key) => sum + sceneDurations[key], 0) - (order.length - 1) * OVERLAP;
export const TOTAL_SECONDS = TOTAL_FRAMES / FPS;

// The frame recommended as the poster (the Apple default is 5 s; ours is chosen in README).
export const POSTER_FRAME = 130;

// Frames for one-shot sound cues, shared with scripts/make-audio.mjs through audio-cues.json (written by render.sh).
export const sec = (s: number): number => Math.round(s * FPS);

// The hook's key press (local frame of the hook scene, which starts at frame 0).
export const HOOK_PRESS_FRAME = 24;
