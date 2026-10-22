// Emulator only: second finger takes over while the prepared chapter is still sliding.
// Checks a frame with that finger down, then verifies exactly one extra page.
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawn } = require('node:child_process');
const ui = require('./pad-ui.cjs');

assert.match(process.env.HDC_DEVICE, /^127\.0\.0\.1:\d+$/);
assert.equal(ui.run('shell', 'param', 'get', 'const.product.model').trim(), 'emulator');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const status = items => items.find(n => n.type === 'Text' && /章 · .*屏/.test(n.text))?.text || '';

async function main() {
  ui.run('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', 'com.healing1.readbooks');
  await pause(1200);
  await ui.leaveReader();
  ui.click('tab_library'); await pause(400);
  ui.click('book_open_7'); await pause(1200);
  ui.click('reader_toc'); await pause(350);
  ui.click('epub_toc_4'); await pause(750);
  let items = ui.nodes(), before = status(items);
  assert(before.startsWith('6 / 445 章 · 1 /'), before);
  const box = ui.bounds(items.find(item => item.id === 'epub_web'));
  const y = Math.round((box[1] + box[3]) / 2);
  const right = box[2] - 160, left = box[0] + 160;
  for (let n = 0; n < 20; n++) {
    const match = before.match(/· (\d+) \/ (\d+) 屏/);
    if (match && match[1] === match[2]) break;
    ui.run('shell', 'uitest', 'uiInput', 'click', String(right), String(y));
    await pause(220); before = status(ui.nodes());
  }
  assert.match(before, /^6 \/ 445 章 · 6 \/ 6 屏$/);
  await pause(500); // The adjacent Web is already prepared before the first contact.
  ui.run('shell', 'uitest', 'uiInput', 'swipe', String(right), String(y), String(right - 1100), String(y), '15000');
  const hdc = path.join(process.env.DEVECO_SDK_HOME, 'default/openharmony/toolchains/hdc.exe');
  let released = false;
  const finger = spawn(hdc, ['-t', process.env.HDC_DEVICE, 'shell', 'uitest', 'uiInput', 'swipe',
    String(right), String(y), String(left), String(y), '500'], { windowsHide: true });
  const finished = new Promise((resolve, reject) => {
    finger.on('error', reject);
    finger.on('exit', code => { released = true; code === 0 ? resolve() : reject(Error('Second touch injection failed')); });
  });
  await pause(3600);
  assert(!released, 'capture must happen during the second contact');
  const capture = ui.run('shell', 'snapshot_display', '-f', '/data/local/tmp/readbooks-continuation.jpeg');
  assert.match(capture, /success: snapshot display/);
  assert(!released, 'capture must precede the second release');
  ui.run('file', 'recv', '/data/local/tmp/readbooks-continuation.jpeg',
    path.join(__dirname, '../docs/qa/epub-continuation-finger-down.jpeg'));
  await finished; await pause(650);
  const after = status(ui.nodes());
  assert.match(after, /^7 \/ 445 章 · 2 \/ 4 屏$/, 'the second held swipe must reach the next chapter’s second page');
  await ui.leaveReader();
  console.log(JSON.stringify({ before, after, secondFingerCapturedBeforeRelease: true }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
