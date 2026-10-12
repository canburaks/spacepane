#!/usr/bin/env node
// Renders the SpacePane app preview film.
//
//   node script/store-preview/design/render.mjs            full render: frames, encode, poster
//   node script/store-preview/design/render.mjs --draft    quick look: 1x frames, every 3rd frame, no encode
//   node script/store-preview/design/render.mjs --stills 1.25,5.0,12   single frames (seconds) as PNG, 1920x1080
//   node script/store-preview/design/render.mjs --sheet 9.8,10.5,12    contact sheet: 12 frames from 9.8 s to 10.5 s
//   node script/store-preview/design/render.mjs --encode-only          re-encode the frames already rendered
//
// The film (film/index.html) is a pure function of time. Each frame is laid out with window.renderAt(seconds) in
// headless Chromium, captured at twice the output size, then scaled down and encoded by ffmpeg. Nothing is recorded
// in real time and nothing on the visible screen is touched.
//
// Uses Playwright from the website checkout's node_modules (no install here) and ffmpeg/ffprobe from PATH. The checkout
// is the spacepane-web repository: SPACEPANE_WEB_REPO, or ../spacepane-web beside this repository.

import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../../..');
const WORK = path.join(ROOT, '.build/store-preview/design');
const DELIVER = path.join(ROOT, 'docs/release/store-listing/app-preview/design');
const PAGE = pathToFileURL(path.join(HERE, 'film/index.html')).href;
const POSTER_SECONDS = 5.0; // the recommended poster frame; see README.md

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const value = (name, fallback) => (args.includes(`--${name}`) ? args[args.indexOf(`--${name}`) + 1] : fallback);

const draft = flag('draft');
const scale = Number(value('scale', draft ? 1 : 2));
const step = Number(value('step', draft ? 3 : 1));
const workers = Number(value('workers', 8));
const framesDir = path.join(WORK, draft ? 'draft' : 'frames');

const WEB_REPO = path.resolve(process.env.SPACEPANE_WEB_REPO ?? path.join(ROOT, '../spacepane-web'));
if (!fs.existsSync(path.join(WEB_REPO, 'package.json'))) {
  console.error(
    `The spacepane-web checkout was not found at ${WEB_REPO}. Playwright is taken from its node_modules: ` +
      'check it out beside this repository, or set SPACEPANE_WEB_REPO to its path.',
  );
  process.exit(1);
}
const requireFromWeb = createRequire(path.join(WEB_REPO, 'package.json'));
const { chromium } = requireFromWeb('playwright');

function run(command, commandArgs, options = {}) {
  const result = spawnSync(command, commandArgs, { stdio: options.quiet ? 'pipe' : 'inherit', encoding: 'utf8' });
  if (result.status !== 0) {
    if (options.quiet) process.stderr.write(result.stderr || '');
    throw new Error(`${command} failed with status ${result.status}`);
  }
  return result.stdout;
}

async function openPage(browser, deviceScaleFactor) {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor, colorScheme: 'light' });
  const page = await context.newPage();
  page.on('pageerror', (error) => { console.error(`page error: ${error.message}`); process.exitCode = 1; });
  page.on('console', (message) => { if (message.type() === 'error') console.error(`page console: ${message.text()}`); });
  await page.goto(PAGE);
  const film = await page.evaluate(() => window.ready);
  const cdp = await context.newCDPSession(page);
  const shoot = async (seconds) => {
    await page.evaluate((t) => { window.renderAt(t); return new Promise((resolve) => requestAnimationFrame(() => resolve())); }, seconds);
    const { data } = await cdp.send('Page.captureScreenshot', { format: 'png', optimizeForSpeed: true });
    return Buffer.from(data, 'base64');
  };
  return { page, film, shoot, close: () => context.close() };
}

async function launch() {
  return chromium.launch({ args: ['--allow-file-access-from-files', '--force-color-profile=srgb', '--font-render-hinting=none', '--hide-scrollbars'] });
}

async function renderStills(list) {
  const out = path.join(WORK, 'stills');
  fs.mkdirSync(out, { recursive: true });
  const browser = await launch();
  const { shoot, close } = await openPage(browser, Number(value('scale', 1)));
  for (const seconds of list) {
    const file = path.join(out, `t${seconds.toFixed(2).padStart(5, '0')}.png`);
    fs.writeFileSync(file, await shoot(seconds));
    console.log(file);
  }
  await close();
  await browser.close();
}

async function renderFrames() {
  fs.rmSync(framesDir, { recursive: true, force: true });
  fs.mkdirSync(framesDir, { recursive: true });
  const browser = await launch();
  const first = await openPage(browser, scale);
  const film = first.film;

  // Determinism check: the same frame rendered twice, in a different order, must be byte-identical.
  const probe = [12.2, 3.1, 12.2];
  const hashes = [];
  for (const seconds of probe) hashes.push(createHash('sha256').update(await first.shoot(seconds)).digest('hex'));
  if (hashes[0] !== hashes[2]) throw new Error('the film is not deterministic: one frame rendered twice differs');
  await first.close();

  const frames = [];
  for (let frame = 0; frame < film.frames; frame += step) frames.push(frame);
  await browser.close();
  let done = 0;
  const started = Date.now();
  // One browser per worker, not one page per worker: pages that share a browser share its raster caches, and
  // frames then differed between runs by one level in a few pixels. Separate browsers give identical frames.
  // Each worker takes a fixed, contiguous run of frames, so every page meets the same frames in the same order on
  // every render (a page's raster is not wholly independent of the frame it drew before).
  const count = Math.min(workers, frames.length);
  await Promise.all(Array.from({ length: count }, async (unused, worker) => {
    const own = await launch();
    const { shoot, close } = await openPage(own, scale);
    const end = Math.floor(((worker + 1) * frames.length) / count);
    for (let index = Math.floor((worker * frames.length) / count); index < end; index++) {
      const frame = frames[index];
      const name = `f_${String(draft ? frame : frame).padStart(5, '0')}.png`;
      fs.writeFileSync(path.join(framesDir, name), await shoot(frame / film.fps));
      done += 1;
      if (done % 60 === 0 || done === frames.length) process.stdout.write(`\r  frames ${done}/${frames.length}  ${((Date.now() - started) / 1000).toFixed(0)}s`);
    }
    await close();
    await own.close();
  }));
  process.stdout.write('\n');
  return film;
}

function encode(film) {
  fs.mkdirSync(DELIVER, { recursive: true });
  const output = path.join(DELIVER, 'spacepane-preview.mp4');
  const seconds = (film.frames / film.fps).toFixed(3);
  // Lanczos down to 1920x1080, BT.709 limited range, then a faint luma dither so the gradients do not band. The
  // dither is a fixed pattern (no temporal flag): grain that changes every frame cannot be afforded at 10-12 Mbps
  // and turned the wipes blotchy in a first encode.
  const filters = [
    'scale=1920:1080:flags=lanczos+accurate_rnd+full_chroma_int:in_range=pc:out_range=tv:out_color_matrix=bt709',
    'format=yuv420p',
    'noise=c0s=3:c0f=u',
    'setparams=range=tv:color_primaries=bt709:color_trc=bt709:colorspace=bt709',
  ].join(',');
  const common = [
    '-hide_banner', '-loglevel', 'error', '-y',
    '-framerate', String(film.fps), '-start_number', '0', '-i', path.join(framesDir, 'f_%05d.png'),
    '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo',
    '-t', seconds, '-vf', filters,
    // One encoder thread: x264's rate control under a VBV limit is not repeatable across threads, and the same
    // frames should give the same file.
    '-c:v', 'libx264', '-threads', '1', '-profile:v', 'high', '-level:v', '4.0', '-preset', 'slow', '-pix_fmt', 'yuv420p',
    '-b:v', '11M', '-maxrate', '12M', '-bufsize', '24M', '-r', String(film.fps), '-g', String(film.fps * 2), '-bf', '2',
    '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', '-color_range', 'tv',
    '-x264-params', 'colorprim=bt709:transfer=bt709:colormatrix=bt709:aq-mode=3',
  ];
  const log = path.join(WORK, 'x264-2pass');
  run('ffmpeg', [...common, '-pass', '1', '-passlogfile', log, '-an', '-f', 'mp4', '/dev/null']);
  run('ffmpeg', [...common, '-pass', '2', '-passlogfile', log,
    '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-ac', '2', '-movflags', '+faststart', '-bitexact', output]);
  // The poster is the frame the video itself shows at POSTER_SECONDS.
  run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-ss', String(POSTER_SECONDS), '-i', output, '-frames:v', '1',
    '-vf', 'scale=in_color_matrix=bt709:in_range=tv:out_range=pc,format=rgb24', path.join(DELIVER, 'poster.png')]);
  console.log(run('ffprobe', ['-v', 'error', '-show_entries',
    'format=duration,size,bit_rate:stream=index,codec_name,profile,level,width,height,pix_fmt,r_frame_rate,avg_frame_rate,nb_frames,bit_rate,sample_rate,channels,channel_layout,field_order',
    '-of', 'default=noprint_wrappers=1', output], { quiet: true }));
  console.log(output);
}

// A contact sheet for checking motion: `count` frames from `from` to `to` seconds, tiled three across.
async function renderSheet(from, to, count) {
  const out = path.join(WORK, 'sheets');
  const tmp = path.join(out, 'tmp');
  fs.rmSync(tmp, { recursive: true, force: true });
  fs.mkdirSync(tmp, { recursive: true });
  const browser = await launch();
  const { shoot, close } = await openPage(browser, 1);
  for (let i = 0; i < count; i++) {
    const seconds = count === 1 ? from : from + ((to - from) * i) / (count - 1);
    fs.writeFileSync(path.join(tmp, `s_${String(i).padStart(3, '0')}.png`), await shoot(seconds));
  }
  await close();
  await browser.close();
  const file = path.join(out, `sheet_${from.toFixed(2)}_${to.toFixed(2)}.png`);
  run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-framerate', '1', '-i', path.join(tmp, 's_%03d.png'),
    '-vf', `scale=640:360:flags=lanczos,tile=3x${Math.ceil(count / 3)}:padding=6:color=0x202020`, '-frames:v', '1', file]);
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(file);
}

if (flag('sheet')) {
  const [from, to, count] = value('sheet').split(',').map(Number);
  await renderSheet(from, to, count || 12);
} else if (flag('stills')) {
  await renderStills(value('stills').split(',').map(Number));
} else if (flag('encode-only')) {
  const count = fs.readdirSync(framesDir).filter((name) => name.endsWith('.png')).length;
  encode({ fps: 30, frames: count });
} else {
  const film = await renderFrames();
  if (!draft && step === 1 && !flag('no-encode')) encode(film);
}
