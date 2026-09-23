// Emulator only: preserve resting text margins, expose screen-edge drawing DURING an intra-chapter drag.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const ui = require('./pad-ui.cjs');
const device = process.env.HDC_DEVICE;
assert.match(device, /^127\.0\.0\.1:\d+$/);
assert.equal(ui.run('shell', 'param', 'get', 'const.product.model').trim(), 'emulator');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const status = () => ui.nodes().find(n => n.type === 'Text' && /章 · .*屏/.test(n.text))?.text || '';
async function click(id) { ui.click(id); await pause(450); }
async function main() {
  await ui.leaveReader(); await click('tab_library'); await click('book_open_7'); await pause(1400);
  await click('reader_toc'); await click('epub_toc_4'); await pause(1000);
  const b = ui.bounds(ui.nodes().find(n => n.id === 'epub_web'));
  assert.equal(b[0], 0, 'native Web clipping must start at screen edge');
  const y = Math.round((b[1] + b[3]) / 2);
  ui.run('shell', 'uitest', 'uiInput', 'click', String(b[2] - 160), String(y)); await pause(450);
  const before = status(); assert.match(before, /^6 \/ 445 章 · 2 \/ /);
  ui.screen('epub-original-reading-margins');
  const hdc = path.join(process.env.DEVECO_SDK_HOME, 'default/openharmony/toolchains/hdc.exe');
  const perf = spawn(hdc, ['-t', device, 'shell', 'SP_daemon', '-N', '6', '-PKG', 'com.healing1.readbooks', '-f'], { windowsHide: true });
  let perfText = ''; perf.stdout.on('data', chunk => perfText += chunk);
  const measured = new Promise((resolve, reject) => { perf.on('error', reject); perf.on('exit', code => code === 0 ? resolve() : reject(Error('Performance sampler failed'))); });
  await pause(250);
  let released = false;
  const input = spawn(hdc, ['-t', device, 'shell', 'uitest', 'uiInput', 'swipe', String(b[2] - 160), String(y), String(b[0] + 160), String(y), '500'], { windowsHide: true });
  const finished = new Promise((resolve, reject) => { input.on('error', reject); input.on('exit', code => { released = true; code === 0 ? resolve() : reject(Error('Gesture failed')); }); });
  await pause(2300); assert(!released);
  ui.run('shell', 'snapshot_display', '-f', '/data/local/tmp/readbooks-edge-drag.jpeg');
  assert(!released, 'capture must not wait until touch release');
  ui.run('file', 'recv', '/data/local/tmp/readbooks-edge-drag.jpeg', path.join(__dirname, '../docs/qa/epub-screen-edge-drag.jpeg'));
  await finished; await measured; await pause(500);
  const after = status(); assert.match(after, /^6 \/ 445 章 · 3 \/ /);
  ui.screen('epub-restored-reading-margins');
  fs.writeFileSync(path.join(__dirname, '../docs/qa/epub-edge-drag-perf.txt'),
    'Emulator-only, continuous injected swipe plus idle lead/tail. Includes independent screenshot overhead; not Pad FPS or a guaranteed sustained rate.\n' + perfText);
  await ui.leaveReader();
  console.log(JSON.stringify({ before, after, fullWidthWeb: b, screenshotBeforeRelease: true }));
  console.log(perfText);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
