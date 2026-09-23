// Real slow touch + independent screen capture while the finger is STILL DOWN.
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawn } = require('node:child_process');
const ui = require('./pad-ui.cjs');
const device = process.env.HDC_DEVICE;
assert.match(device, /^127\.0\.0\.1:\d+$/);
assert.equal(ui.run('shell', 'param', 'get', 'const.product.model').trim(), 'emulator');
const pause = ms => new Promise(r => setTimeout(r, ms));
const status = items => items.find(n => n.type === 'Text' && /章 · .*屏/.test(n.text))?.text || '';
async function click(id) { ui.click(id); await pause(500); }
async function main() {
  await ui.leaveReader();
  await click('tab_library'); await click('book_open_7'); await pause(1400);
  await click('reader_toc'); await click('epub_toc_4'); await pause(1000);
  let items = ui.nodes();
  assert(status(items).startsWith('6 / 445'));
  const b = ui.bounds(items.find(n => n.id === 'epub_web'));
  const y = Math.round((b[1] + b[3]) / 2);
  let match = status(items).match(/· (\d+) \/ (\d+) 屏/);
  while (match[1] !== match[2]) {
    ui.run('shell', 'uitest', 'uiInput', 'click', String(b[2] - 60), String(y));
    await pause(180); items = ui.nodes(); match = status(items).match(/· (\d+) \/ (\d+) 屏/);
  }
  await pause(700);
  const hdc = path.join(process.env.DEVECO_SDK_HOME, 'default/openharmony/toolchains/hdc.exe');
  let released = false;
  const input = spawn(hdc, ['-t', device, 'shell', 'uitest', 'uiInput', 'swipe', String(b[2] - 140), String(y), String(b[0] + 140), String(y), '500'], { windowsHide: true });
  const finished = new Promise((resolve, reject) => { input.on('error', reject); input.on('exit', code => { released = true; code === 0 ? resolve() : reject(Error('Touch injection failed')); }); });
  await pause(2200);
  assert(!released, 'capture must occur before the release, not after activation');
  console.log(ui.run('shell', 'snapshot_display', '-f', '/data/local/tmp/readbooks-half-drag.jpeg'));
  assert(!released, 'screen capture must not queue behind completed touch injection');
  ui.run('file', 'recv', '/data/local/tmp/readbooks-half-drag.jpeg', path.join(__dirname, '../docs/qa/epub-next-chapter-half-drag.jpeg'));
  await finished; await pause(600);
  assert(status(ui.nodes()).startsWith('7 / 445'), 'slow held swipe commits exactly one next chapter');
  ui.screen('epub-next-chapter-drag-complete');
  await click('reader_toc'); await click('epub_toc_4'); await pause(600); await click('reader_back');
  console.log('Captured the boundary before finger release; next chapter must be visually present alongside outgoing text. Slow release committed once.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
