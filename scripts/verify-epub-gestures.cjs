// Emulator-only real touch-input smoke test. This validates navigation, not display FPS.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ui = require('./pad-ui.cjs');
assert.match(process.env.HDC_DEVICE, /^127\.0\.0\.1:\d+$/);
assert.equal(ui.run('shell', 'param', 'get', 'const.product.model').trim(), 'emulator');
const pause = ms => new Promise(r => setTimeout(r, ms));
const status = list => list.find(n => n.type === 'Text' && /章 · .*屏/.test(n.text))?.text || '';
async function click(id) { ui.click(id); await pause(450); }
async function main() {
  ui.run('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', 'com.healing1.readbooks'); await pause(1200);
  await ui.leaveReader();
  await click('tab_library'); await click('book_open_7'); await pause(1200);
  await click('reader_toc'); await click('epub_toc_4'); await pause(700);
  const initial = ui.nodes(), before = status(initial), count = Number(before.match(/· 1 \/ (\d+) 屏/)[1]);
  assert(before.startsWith('6 / 445'));
  const b = ui.bounds(initial.find(n => n.id === 'epub_web'));
  const y = Math.round((b[1] + b[3]) / 2), left = b[0] + 160, right = b[2] - 160;
  for (let n = 0; n < count + 2; n++) {
    ui.run('shell', 'uitest', 'uiInput', 'swipe', String(right), String(y), String(left), String(y), '15000');
  }
  await pause(600);
  const after = status(ui.nodes());
  assert.match(after, /^7 \/ 445 章 · 3 \/ \d+ 屏$/, 'all swipes, including the chapter boundary, advance once');
  ui.screen('shaosong-rapid-swipes');
  await click('reader_toc'); await click('epub_toc_4'); await pause(450);
  await click('reader_back'); await click('tab_home');
  const result = { before, after, forwardSwipes: count + 2, scope: 'Sequential HDC touch swipes at 15000 px/s; navigation accounting only, not a GPU frame-rate measurement.' };
  fs.writeFileSync(path.join(__dirname, '../docs/qa/epub-gestures.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
}
main().catch(e => { console.error(e); process.exitCode = 1; });
