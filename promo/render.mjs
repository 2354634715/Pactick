import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import crypto from 'node:crypto';
import { serve } from './server.mjs';

const directory = path.dirname(fileURLToPath(import.meta.url));
const project = path.resolve(directory, '..');
const temporary = path.join(project, '.cache/promo-tmp');
fs.mkdirSync(temporary, { recursive: true });
process.env.TEMP = temporary;
process.env.TMP = temporary;
const arguments_ = process.argv.slice(2);
function arg(name, fallback) { const i = arguments_.indexOf(name); return i < 0 ? fallback : arguments_[i + 1]; }
const width = Number(arg('--width', '1920'));
const height = Math.round(width * 9 / 16);
const fps = Number(arg('--fps', '30'));
const workers = Number(arg('--workers', '3'));
const duration = 60;
if (!Number.isInteger(width) || width < 640 || width > 3840 || width % 32 || ![24, 30, 60].includes(fps) || !Number.isInteger(workers) || workers < 1 || workers > 8) {
  throw new Error('宽度须为 640..3840 的 32 倍数；帧率为 24/30/60；并行数为 1..8。');
}
const output = path.resolve(arg('--output', path.join(project, 'output', 'pactick-promo-swiss')));
fs.mkdirSync(output, { recursive: true });
function findPlaywright() {
  const candidates = [process.env.PLAYWRIGHT_MODULE_DIR, path.join(project, '.cache/promo-node/node_modules/playwright')].filter(Boolean);
  const cache = path.join(os.homedir(), 'AppData/Local/npm-cache/_npx');
  if (fs.existsSync(cache)) for (const entry of fs.readdirSync(cache)) candidates.push(path.join(cache, entry, 'node_modules/playwright'));
  const require = createRequire(import.meta.url);
  for (const candidate of candidates) if (fs.existsSync(path.join(candidate, 'package.json'))) return require(candidate);
  try { return require('playwright'); } catch { throw new Error('未找到 Playwright。设置 PLAYWRIGHT_MODULE_DIR，或按 GUIDE.md 安装到项目缓存。'); }
}
function findFFmpeg() {
  if (process.env.FFMPEG_PATH) return process.env.FFMPEG_PATH;
  const binaries = path.join(project, '.cache/promo-python/imageio_ffmpeg/binaries');
  if (fs.existsSync(binaries)) {
    const file = fs.readdirSync(binaries).find(n => n.startsWith('ffmpeg') && (process.platform !== 'win32' || n.endsWith('.exe')));
    if (file) return path.join(binaries, file);
  }
  return 'ffmpeg';
}
function encoder(ffmpegArgs) {
  const process_ = spawn(findFFmpeg(), ffmpegArgs, { windowsHide: true, stdio: ['pipe', 'ignore', 'pipe'] });
  let errorText = '';
  process_.stderr.on('data', d => { errorText = (errorText + d.toString()).slice(-16000); });
  process_.stdin.on('error', () => {});
  const completion = new Promise((resolve, reject) => {
    process_.on('error', reject);
    process_.on('close', code => code === 0 ? resolve() : reject(new Error(`FFmpeg ${code}: ${errorText}`)));
  });
  // 保存失败结果，避免编码进程早退时产生未处理的拒绝。
  let failure;
  completion.catch(e => { failure = e; });
  return { process_: process_, completion, check: () => { if (failure) throw failure; } };
}
const playwright = findPlaywright();
const server = await serve(0);
const base = `http://127.0.0.1:${server.address().port}`;
const browserPaths = [process.env.PACTICK_BROWSER, 'C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].filter(Boolean);
const executablePath = browserPaths.find(p => fs.existsSync(p));
let browser;
const errors = [];
async function pageAt() {
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(`${base}/index.html?export=1`, { waitUntil: 'networkidle' });
  await page.evaluate(() => window.filmReady);
  if (!(await page.evaluate(() => document.fonts.check('700 96px NotoSC')))) throw new Error('中文字体未加载，检查 PACTICK_CJK_FONT。');
  await page.evaluate(({ width, height }) => { const c = document.querySelector('canvas'); c.width = width; c.height = height; }, { width, height });
  return page;
}
async function canvasImage(page, t, format = 'image/jpeg') {
  const base64 = await page.evaluate(({ t, format }) => {
    window.PactickFilm.renderAt(t);
    return document.querySelector('canvas').toDataURL(format, .97).split(',')[1];
  }, { t, format });
  return Buffer.from(base64, 'base64');
}
try {
  browser = await playwright.chromium.launch({ headless: true, executablePath, args: ['--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--mute-audio'] });
  const page = await pageAt();
  const spec = await page.evaluate(() => ({ ...window.PactickFilm, renderAt: undefined }));
  const chapters = spec.chapters;
  // 首帧是可读的封面；正文逐字从第一秒开始进入。
  const stillTimes = [3.5, 11.5, 19.5, 28.5, 37.5, 45.5, 53.5, 58.5];
  for (let i = 0; i < stillTimes.length; i++) {
    fs.writeFileSync(path.join(output, `frame-${String(i).padStart(2, '0')}.png`), await canvasImage(page, stillTimes[i], 'image/png'));
  }
  fs.writeFileSync(path.join(output, 'cover.png'), await canvasImage(page, 3.5, 'image/png'));
  fs.writeFileSync(path.join(output, 'storyboard.json'), JSON.stringify({ width, height, fps, duration, chapters, stillTimes, palette:spec.palette }, null, 2));
  console.log('已输出 8 张章节检查图及封面。');
  await page.close();
  if (!arguments_.includes('--stills')) {
    const soundtrack = path.join(output, 'soundtrack.wav');
    if (!fs.existsSync(soundtrack)) throw new Error('缺少 soundtrack.wav，先运行 synth_audio.py。');
    const total = duration * fps;
    const started = performance.now();
    let completed = 0;
    const segments = await Promise.all(Array.from({ length: workers }, async (_, worker) => {
      const first = Math.floor(worker * total / workers), last = Math.floor((worker + 1) * total / workers);
      const framePage = await pageAt();
      const filename = path.join(output, `segment-${worker}.mp4`);
      const enc = encoder(['-y', '-hide_banner', '-loglevel', 'error', '-f', 'image2pipe', '-vcodec', 'mjpeg', '-framerate', String(fps), '-i', 'pipe:0', '-an', '-vf', 'scale=in_range=full:out_range=tv:in_color_matrix=bt601:out_color_matrix=bt709,format=yuv420p', '-c:v', 'libx264', '-preset', 'fast', '-crf', '17', '-pix_fmt', 'yuv420p', '-color_range', 'tv', '-colorspace', 'bt709', '-color_trc', 'bt709', '-color_primaries', 'bt709', '-threads', '2', '-video_track_timescale', '30000', filename]);
      try {
        for (let f = first; f < last; f++) {
          enc.check();
          const bytes = await canvasImage(framePage, f / fps);
          if (!enc.process_.stdin.write(bytes)) await once(enc.process_.stdin, 'drain');
          completed++;
          if (completed % 150 === 0) console.log(`已渲染 ${completed}/${total} 帧 · ${Math.round((performance.now() - started) / 1000)}s`);
        }
        enc.process_.stdin.end();
        await enc.completion;
        return filename;
      } catch (e) { enc.process_.kill(); throw e; }
      finally { await framePage.close(); }
    }));
    const list = path.join(output, 'concat.txt');
    fs.writeFileSync(list, segments.map(f => `file '${path.basename(f)}'`).join('\n') + '\n');
    const movie = path.join(output, 'Pactick-Swiss-60s.mp4');
    const mux = encoder(['-y', '-hide_banner', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', list, '-i', soundtrack, '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-t', '60', '-movflags', '+faststart', '-metadata', 'title=Pactick — 计划，变成行动', '-metadata', 'comment=Original code-generated motion graphics and synthesized soundtrack. Android preview; conceptual feature illustration.', movie]);
    mux.process_.stdin.end();
    await mux.completion;
    const sourceFiles = ['film.js', 'index.html', 'render.mjs', 'server.mjs', 'synth_audio.py'];
    const sourceSHA256 = Object.fromEntries(sourceFiles.map(file => [file, crypto.createHash('sha256').update(fs.readFileSync(path.join(directory, file))).digest('hex')]));
    fs.writeFileSync(path.join(output, 'render-manifest.json'), JSON.stringify({ project:'Pactick', width, height, fps, duration, frameCount:total, format:'H.264 / AAC', colorSpace:'bt709 / limited / yuv420p', generatedAt:new Date().toISOString(), sourceSHA256, movieSHA256:crypto.createHash('sha256').update(fs.readFileSync(movie)).digest('hex'), browserVersion:browser.version(), errors, reference:'https://www.bilibili.com/video/BV1hWar6SEVP/', referenceAccess:'作者的完整视频简介与风格说明；未获取播放内容或字幕', font:'Arial (system) + Noto Sans SC (system)', visuals:'Canvas 2D; no image, footage, or recorded app screen assets', audio:'Original Python/numpy synthesized stereo soundtrack; no voiceover', releaseState:'Android 0.2.0-preview.1; conceptual feature illustration' }, null, 2));
    console.log(`完成：${movie}`);
  }
  if (errors.length) throw new Error(`浏览器错误：${errors.join('; ')}`);
} finally {
  if (browser) await browser.close();
  await new Promise(resolve => server.close(resolve));
}
