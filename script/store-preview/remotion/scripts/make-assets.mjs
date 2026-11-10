// Copies the real captures and the icon into public/, and writes the generated assets
// (dither-noise tile). Run from the project root: npm run assets
import {copyFileSync, mkdirSync, existsSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const repo = resolve(root, '../../..');
const raw = resolve(repo, '.build/store-screenshots/raw');
const captures = [
  '1-finder', '1-panel', '2-panel', '3-panel', '4-panel-summary', '4-panel-table',
  '5-panel', '6-panel', '8-app', '9-app',
];

mkdirSync(resolve(root, 'public/captures'), {recursive: true});
for (const name of captures) {
  const from = resolve(raw, `${name}.png`);
  if (!existsSync(from)) throw new Error(`Missing capture ${from}`);
  copyFileSync(from, resolve(root, `public/captures/${name}.png`));
}
copyFileSync(resolve(repo, 'Configuration/AppIcon.svg'), resolve(root, 'public/icon.svg'));

// A 256 px grey noise tile used at very low opacity over the gradient to dither it (no banding after H.264).
execFileSync('ffmpeg', [
  '-y', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=0x808080:s=256x256',
  '-vf', 'noise=alls=60:allf=u:all_seed=7', '-frames:v', '1', resolve(root, 'public/noise.png'),
]);
console.log('assets ready');
