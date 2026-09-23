// Emulator fixture only: cancelled short drag and prepared forward/backward chapter edges.
const assert = require('node:assert/strict');
const ui = require('./pad-ui.cjs');
assert.match(process.env.HDC_DEVICE, /^127\.0\.0\.1:\d+$/);
assert.equal(ui.run('shell', 'param', 'get', 'const.product.model').trim(), 'emulator');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const status = () => ui.nodes().find(n => n.type === 'Text' && /章 · .*屏/.test(n.text))?.text || '';
async function click(id) { ui.click(id); await pause(450); }
async function swipe(x1, x2, y) {
  ui.run('shell', 'uitest', 'uiInput', 'swipe', String(x1), String(y), String(x2), String(y), '4000');
  await pause(550);
}
async function main() {
  await ui.leaveReader(); await click('tab_library'); await click('book_open_7'); await pause(1300);
  await click('reader_toc'); await click('epub_toc_4'); await pause(1000);
  const b = ui.bounds(ui.nodes().find(n => n.id === 'epub_web'));
  const y = Math.round((b[1] + b[3]) / 2), right = b[2] - 160, left = b[0] + 160;
  let before = status();
  for (let turn = 0; turn < 30; turn++) {
    assert(before.startsWith('6 / 445'), 'Unexpected fixture chapter: ' + before);
    const pages = before.match(/· (\d+) \/ (\d+) 屏/);
    if (pages && pages[1] === pages[2]) break;
    ui.run('shell', 'uitest', 'uiInput', 'click', String(right), String(y));
    await pause(250); before = status();
  }
  const edge = before.match(/· (\d+) \/ (\d+) 屏/);
  assert(edge && edge[1] === edge[2], 'Did not reach the last screen');
  await pause(800);
  await swipe(right, right - 40, y);
  assert.equal(status(), before, 'Short drag must cancel without changing chapter');
  await swipe(right, left, y);
  const forward = status();
  assert(forward.startsWith('7 / 445 章 · 1 /'), 'Forward commit failed: ' + forward);
  await swipe(left, right, y);
  assert.equal(status(), before, 'Backwards swipe must reveal the previous last screen');
  ui.screen('epub-boundary-return-verified');
  await ui.leaveReader();
  console.log(JSON.stringify({ cancelledShortDrag: true, before, forward, backward: before }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
