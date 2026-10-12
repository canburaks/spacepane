// Synthesises the preview's soundtrack (no samples, no third-party audio): a soft key thunk on the
// Space press, a faint tick at each scene change and a quiet chord under the end card.
// Output: public/audio/score.wav (48 kHz, 16-bit, stereo). Cue frames come from src/theme/timing.ts.
import {mkdirSync, writeFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {FPS, HOOK_PRESS_FRAME, TOTAL_FRAMES, sceneStart} from '../src/theme/timing.ts';

const SR = 48000;
const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(here, '../public/audio/score.wav');
const seconds = TOTAL_FRAMES / FPS;
const n = Math.ceil(seconds * SR);
const L = new Float32Array(n);
const R = new Float32Array(n);

let seed = 12345; // deterministic noise so renders are repeatable
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 0xffffffff) * 2 - 1;

const add = (t0, dur, fn, pan = 0) => {
  const i0 = Math.floor(t0 * SR);
  const len = Math.floor(dur * SR);
  const gl = Math.cos(((pan + 1) * Math.PI) / 4);
  const gr = Math.sin(((pan + 1) * Math.PI) / 4);
  for (let i = 0; i < len && i0 + i < n; i++) {
    const v = fn(i / SR, i / len);
    L[i0 + i] += v * gl;
    R[i0 + i] += v * gr;
  }
};

// Key thunk: a falling sine plus a short filtered click.
const thunk = (t0, gain) => {
  let phase = 0;
  let lp = 0;
  add(t0, 0.28, (t, p) => {
    const f = 55 + 110 * Math.exp(-t * 28);
    phase += (2 * Math.PI * f) / SR;
    lp += 0.18 * (rnd() - lp);
    return gain * (Math.sin(phase) * Math.exp(-t * 16) + lp * 1.4 * Math.exp(-t * 90));
  });
};

// Tick: a short soft blip with a touch of air.
const tick = (t0, gain, f, pan) => {
  let phase = 0;
  let lp = 0;
  add(t0, 0.22, (t) => {
    phase += (2 * Math.PI * f) / SR;
    lp += 0.25 * (rnd() - lp);
    return gain * (Math.sin(phase) * Math.exp(-t * 26) + lp * 0.5 * Math.exp(-t * 40));
  }, pan);
};

// End chord: A major add9, slow attack, long tail.
const chord = (t0, gain) => {
  const notes = [220, 329.63, 440, 554.37, 659.25];
  notes.forEach((f, k) => {
    const pan = (k - 2) * 0.18;
    for (const detune of [0.997, 1.003]) {
      let phase = 0;
      add(t0, 2.6, (t, p) => {
        phase += (2 * Math.PI * f * detune) / SR;
        const env = Math.min(1, t / 0.35) * Math.exp(-t * 1.25);
        return gain * 0.5 * Math.sin(phase) * env * (k === 0 ? 1.3 : 0.8);
      }, pan);
    }
  });
};

thunk(HOOK_PRESS_FRAME / FPS, 0.55);
const ids = ['secrets', 'database', 'archive', 'notebook', 'markdown', 'model', 'settings'];
ids.forEach((id, k) => tick(sceneStart(id) / FPS + 0.02, 0.07, 1500 + (k % 3) * 160, k % 2 ? 0.25 : -0.25));
thunk(sceneStart('end') / FPS + 8 / FPS, 0.3);
chord(sceneStart('end') / FPS + 0.2, 0.16);

// Fade the last 0.5 s, then normalise to a -3 dBFS peak and write 16-bit PCM.
const fade = Math.floor(0.5 * SR);
for (let i = 0; i < fade; i++) {
  const g = i / fade;
  L[n - 1 - i] *= g;
  R[n - 1 - i] *= g;
}
let peak = 0;
for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
const scale = peak > 0 ? 0.708 / peak : 1;
const data = Buffer.alloc(n * 4);
for (let i = 0; i < n; i++) {
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[i] * scale)) * 32767), i * 4);
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[i] * scale)) * 32767), i * 4 + 2);
}
const header = Buffer.alloc(44);
header.write('RIFF', 0);
header.writeUInt32LE(36 + data.length, 4);
header.write('WAVEfmt ', 8);
header.writeUInt32LE(16, 16);
header.writeUInt16LE(1, 20);
header.writeUInt16LE(2, 22);
header.writeUInt32LE(SR, 24);
header.writeUInt32LE(SR * 4, 28);
header.writeUInt16LE(4, 32);
header.writeUInt16LE(16, 34);
header.write('data', 36);
header.writeUInt32LE(data.length, 40);
mkdirSync(dirname(out), {recursive: true});
writeFileSync(out, Buffer.concat([header, data]));
console.log(`score.wav: ${seconds.toFixed(2)} s, peak scale ${scale.toFixed(3)}`);
