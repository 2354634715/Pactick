/* 检查实际成片的元数据、预览交互与时间轴；不修改动画和音频。 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { serve } from './server.mjs';
const directory = path.dirname(fileURLToPath(import.meta.url));
const project = path.resolve(directory, '..');
const temporary = path.join(project, '.cache/promo-tmp');
fs.mkdirSync(temporary, { recursive:true });
process.env.TEMP = temporary; process.env.TMP = temporary;
const require = createRequire(import.meta.url);
const candidates = [process.env.PLAYWRIGHT_MODULE_DIR, path.join(project, '.cache/promo-node/node_modules/playwright')].filter(Boolean);
const cache = path.join(os.homedir(), 'AppData/Local/npm-cache/_npx');
if (fs.existsSync(cache)) for (const entry of fs.readdirSync(cache)) candidates.push(path.join(cache, entry, 'node_modules/playwright'));
const modulePath = candidates.find(p => fs.existsSync(path.join(p, 'package.json')));
const { chromium } = modulePath ? require(modulePath) : require('playwright');
const executablePath = [process.env.PACTICK_BROWSER, 'C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].filter(Boolean).find(p => fs.existsSync(p));
const output = path.join(project, 'output/pactick-promo-swiss');
const screenshots = path.join(project, 'output/playwright');
fs.mkdirSync(screenshots, {recursive:true});
const server = await serve(0);
const base = `http://127.0.0.1:${server.address().port}`;
let browser;
const errors = [];
const report = { checks:[], errors, video:null };
try {
  browser = await chromium.launch({headless:true,executablePath,args:['--mute-audio']});
  const page = await browser.newPage({viewport:{width:1440,height:1120}});
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', msg => { if(msg.type() === 'error') errors.push(msg.text()); });
  await page.goto(base, {waitUntil:'networkidle'});
  await page.evaluate(() => window.filmReady);
  assert(await page.evaluate(() => document.fonts.check('700 96px NotoSC')));
  report.checks.push('中文字体完成加载');
  await page.getByRole('button', {name:'播放',exact:true}).click();
  await page.waitForTimeout(900);
  const played = await page.evaluate(() => ({time:Number(document.querySelector('#seek').value), audio:document.querySelector('audio').currentTime, paused:document.querySelector('audio').paused}));
  assert(played.time > .3 && played.audio > .3 && !played.paused, JSON.stringify(played));
  await page.getByRole('button', {name:'暂停',exact:true}).click();
  assert(await page.evaluate(() => document.querySelector('audio').paused));
  report.checks.push('播放与暂停同步控制画面和配乐');
  await page.getByRole('slider', {name:'播放进度'}).evaluate(el => { el.value='26'; el.dispatchEvent(new Event('input',{bubbles:true})); });
  assert.equal(await page.locator('#seek').inputValue(), '26');
  assert.equal(await page.locator('#time').textContent(), '00:26 / 01:00');
  report.checks.push('进度拖动可跳至专注章节');
  await page.getByRole('button', {name:'06 保留自己的记录',exact:true}).click();
  assert.equal(await page.locator('#seek').inputValue(),'50.5');
  report.checks.push('章节跳转准确');
  await page.getByRole('button', {name:'声音开',exact:true}).click();
  assert(await page.evaluate(() => document.querySelector('audio').muted));
  await page.getByRole('button', {name:'声音关',exact:true}).click();
  assert(!(await page.evaluate(() => document.querySelector('audio').muted)));
  report.checks.push('声音开关准确');
  await page.evaluate(() => window.seekFilm(58.5));
  await page.screenshot({path:path.join(screenshots,'pactick-film-desktop.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});
  await page.evaluate(() => window.seekFilm(3.5));
  const viewport = await page.evaluate(() => ({scrollWidth:document.documentElement.scrollWidth,width:innerWidth}));
  assert(viewport.scrollWidth<=viewport.width,JSON.stringify(viewport));
  await page.screenshot({path:path.join(screenshots,'pactick-film-mobile.png'),fullPage:true});
  report.checks.push('390px 预览没有横向溢出');
  const deterministic = await page.evaluate(() => {PactickFilm.renderAt(19.5);const a=document.querySelector('canvas').toDataURL();PactickFilm.renderAt(53.5);PactickFilm.renderAt(19.5);return a===document.querySelector('canvas').toDataURL();});
  assert(deterministic);
  report.checks.push('相同绝对时间渲染相同画面');
  // 在实际转场前后绘制，检查时间索引与浏览器运行错误。
  const count = await page.evaluate(() => {
    const points=[0,.1,7.9,8,8.1,8.4,15.9,16,16.1,16.4,23.9,24,24.1,24.4,33.9,34,34.1,34.4,41.9,42,42.1,42.4,49.9,50,50.1,50.4,55.9,56,56.1,56.4,59.999,60];
    for(const t of points){const r=PactickFilm.renderAt(t);if(r.chapter<0||r.chapter>7)throw Error('章节索引错误');}
    return points.length;
  });
  report.checks.push(`${count} 个转场及首尾时间点通过`);
  report.video = await page.evaluate(async () => {
    const video = document.createElement('video'); video.preload='auto';video.muted=true;video.src='/output/pactick-promo-swiss/Pactick-Swiss-60s.mp4';document.body.append(video);
    await new Promise((resolve,reject) => {video.onloadedmetadata=resolve;video.onerror=()=>reject(Error('成片不能加载'));});
    const meta={duration:video.duration,width:video.videoWidth,height:video.videoHeight};
    for(const t of [1,19.5,37.5,59.8]){await new Promise((resolve,reject)=>{video.onseeked=resolve;video.onerror=()=>reject(Error('成片不能跳转'));video.currentTime=t;});}
    video.remove();return meta;
  });
  assert.equal(report.video.width,1920);assert.equal(report.video.height,1080);assert(Math.abs(report.video.duration-60)<.05,JSON.stringify(report.video));
  report.checks.push('实际 MP4 为 1920×1080 / 60 秒，首中尾均可解码');
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(output,'verification.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
} finally {
  if(browser)await browser.close();
  await new Promise(resolve=>server.close(resolve));
}
