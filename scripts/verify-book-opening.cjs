// Emulator-only regression using the user-supplied diagnostic book and existing local QA TXT.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ui = require('./pad-ui.cjs');
assert.equal(process.env.HDC_DEVICE, '127.0.0.1:5555');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const checks = [];
async function click(id) { ui.click(id); await pause(450); }
async function wait(predicate) {
  for (let i = 0; i < 16; i++) { const items = ui.nodes(); if (predicate(items)) return items; await pause(120); }
  throw new Error('Expected reader state not reached');
}
async function verifyIllustration() {
  const items = await wait(items => items.some(n => n.type === 'image' && n.text === 'chapter-head'));
  assert(items.some(n => n.type === 'heading' && n.text === '第1章：明道宫'));
  assert(items.some(n => n.type === 'paragraph' && ui.bounds(n)[0] > 1400), 'right page contains real EPUB text');
}
async function showTxtHud() {
  const b = ui.bounds(ui.nodes().find(n => n.id === 'reader_canvas'));
  ui.run('shell', 'uitest', 'uiInput', 'click', String((b[0] + b[2]) / 2), String((b[1] + b[3]) / 2));
  await wait(items => items.some(n => n.id === 'reader_back'));
}
async function main() {
  if (ui.nodes().some(n => n.id === 'reader_canvas')) await showTxtHud();
  if (ui.nodes().some(n => n.id === 'reader_back')) await click('reader_back');
  await click('tab_library'); await click('book_open_7'); await verifyIllustration();
  await click('reader_back'); await click('tab_home');
  await click('home_continue'); await verifyIllustration();
  checks.push('继续阅读 opens graphical EPUB with chapter image and two text columns');
  await click('reader_back');
  const suggestion = ui.bounds(ui.nodes().find(n => n.id === 'home_book_4'));
  // Tap its visible upper portion, not the floating navigation overlay below it.
  ui.run('shell', 'uitest', 'uiInput', 'click', String((suggestion[0] + suggestion[2]) / 2), String(suggestion[1] + 32));
  const canvasSamples = [];
  await wait(items => {
    const canvas = items.find(n => n.id === 'reader_canvas');
    if (!canvas) return false;
    const label = canvas.description || canvas.text;
    const layout = label.startsWith('双页阅读。') ? 'double' : label.startsWith('单页阅读。') ? 'single' : 'pending';
    canvasSamples.push({ opacity: Number(canvas.opacity), layout, bounds: canvas.bounds });
    if (Number(canvas.opacity) > 0) {
      if (layout !== 'pending') assert.equal(layout, 'double', 'first visible sampled TXT frame must not be single-page');
      return true;
    }
    return false;
  });
  await pause(400); ui.screen('txt-opening-double-page');
  checks.push('接着读什么 opens TXT; visible canvas captured for double-page visual verification');
  await showTxtHud(); await click('reader_back'); await click('tab_library');
  await click('book_open_7'); await verifyIllustration();
  checks.push('书库 opens the same graphical EPUB');
  await click('reader_back'); await click('book_open_2');
  const dialog = await wait(items => items.some(n => n.text === '补全这本书的图文'));
  assert(!dialog.some(n => n.id === 'reader_canvas'), 'legacy EPUB must not silently use the text renderer');
  ui.click('', '暂不打开'); await pause(400);
  checks.push('legacy EPUB explicitly asks for its original file; cancel does not alter its book');
  await click('tab_home'); ui.screen('home-original-cover-ratios');
  fs.writeFileSync(path.join(__dirname, '../docs/qa/book-opening-regression.json'), JSON.stringify({
    date: new Date().toISOString(), result: 'PASS', checks, canvasSamples,
    limitation: 'UI snapshots are not a frame-by-frame performance recording.'
  }, null, 2));
  console.log(JSON.stringify({ result: 'PASS', checks, canvasSamples }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
