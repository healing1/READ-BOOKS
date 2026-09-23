// Application-only emulator benchmark with the explicitly supplied Shaosong diagnostic copy.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ui = require('./pad-ui.cjs');
assert.match(process.env.HDC_DEVICE, /^127\.0\.0\.1:\d+$/);
assert.equal(ui.run('shell', 'param', 'get', 'const.product.model').trim(), 'emulator');
const label = process.argv[2];
assert(['before', 'after', 'gated', 'prepared'].includes(label));
const pause = ms => new Promise(r => setTimeout(r, ms));
const status = items => items.find(n => n.type === 'Text' && /章 · .*屏/.test(n.text))?.text || '';
async function click(id) { ui.click(id); await pause(450); }
async function wait(predicate) {
  for (let i = 0; i < 20; i++) { const items = ui.nodes(); if (predicate(items)) return items; await pause(150); }
  throw Error('Expected book state not reached');
}
async function main() {
  if (ui.nodes().some(n => n.id === 'reader_back')) await click('reader_back');
  await click('tab_library'); await click('book_open_7');
  await wait(items => items.some(n => n.id === 'epub_web') && status(items));
  await click('reader_settings'); await click('font_default'); await click('reading_settings_close');
  await click('reader_toc'); await click('epub_toc_4');
  await wait(items => status(items).startsWith('6 / 445')); await pause(700);
  const initialLogs = ui.run('shell', 'hilog', '-x', '-T', 'ReadBooksEpubPerf');
  const changes = [];
  for (let chapter = 6; chapter <= 7; chapter++) {
    let items = ui.nodes(), initial = status(items);
    for (let page = 0; page < 25 && status(items).startsWith(chapter + ' / 445'); page++) {
      const b = ui.bounds(items.find(n => n.id === 'epub_web'));
      ui.run('shell', 'uitest', 'uiInput', 'click', String(b[2] - 60), String((b[1] + b[3]) / 2));
      const previous = status(items);
      items = await wait(n => status(n) && status(n) !== previous);
    }
    assert(status(items).startsWith((chapter + 1) + ' / 445'));
    changes.push({ from: initial, to: status(items) });
    await pause(600);
  }
  const logs = ui.run('shell', 'hilog', '-x', '-T', 'ReadBooksEpubPerf');
  const oldLines = new Set(initialLogs.split(/\r?\n/));
  const chapterReady = logs.split(/\r?\n/).filter(line => line.includes('readyMs=') && !oldLines.has(line));
  assert(chapterReady.length >= 2, 'expected native load timings');
  const report = { label, date: new Date().toISOString(), changes, chapterReady,
    scope: label === 'prepared' ? 'Same sample, two chapter boundaries. readyMs measures request to activation of a prepared Web surface, not the subsequent 90 ms native blend or GPU FPS. Neighbours prepare layout and decode illustrations offscreen.' : label === 'gated' ? 'Same sample, default publisher font, two adjacent chapter changes. readyMs includes visible-image dimensions, font readiness and two stable animation frames; image rasterization remains asynchronous. Not GPU FPS, not directly comparable to the old pre-gate timings.' : 'Same sample, default publisher font, two adjacent chapter changes. readyMs covers navigation through layout injection, not GPU frame presentation.' };
  fs.writeFileSync(path.join(__dirname, '../docs/qa/epub-turns-' + label + '.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
  await click('reader_toc'); await click('epub_toc_4');
  await pause(600); await click('reader_back');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
