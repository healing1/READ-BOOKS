// Emulator-only, application-scoped EPUB verification. Run after EpubFixtureRunner.
const assert = require('node:assert/strict');
const ui = require('./pad-ui.cjs');
assert.match(process.env.HDC_DEVICE, /^127\.0\.0\.1:\d+$/, 'Do not run this fixture workflow on a personal device');
assert.equal(ui.run('shell', 'param', 'get', 'const.product.model').trim(), 'emulator');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function wait(predicate) {
  let list;
  for (let i = 0; i < 25; i++) { list = ui.nodes(); if (predicate(list)) return list; await pause(250); }
  throw new Error('Expected EPUB state not reached');
}
async function click(id) {
  if (/^(theme_|layout_)/.test(id)) {
    for (let attempt = 0; attempt < 5; attempt++) {
      const items = ui.nodes(), target = items.find(n => n.id === id);
      const scroll = items.filter(n => n.type === 'Scroll').find(n => {
        const b = ui.bounds(n); return b[2] > b[0] && b[3] > b[1];
      });
      if (!scroll) break;
      const box = ui.bounds(scroll), b = target && ui.bounds(target);
      if (b && b[1] >= box[1] && b[3] <= box[3] && b[3] > b[1]) break;
      ui.run('shell', 'uitest', 'uiInput', 'swipe', String(Math.round((box[0] + box[2]) / 2)),
        String(box[3] - 70), String(Math.round((box[0] + box[2]) / 2)), String(box[1] + 80), '700');
      await pause(350);
    }
  }
  ui.click(id); await pause(350);
}
const screenLabel = list => list.find(n => n.type === 'Text' && /章 · .*屏/.test(n.text))?.text || '';
async function theme(name) { await click('reader_settings'); await click('theme_' + name); await click('reading_settings_close'); await pause(350); }
async function main() {
  await ui.leaveReader();
  await click('tab_library'); await click('book_open_5');
  await wait(list => list.some(n => n.id === 'epub_web') && screenLabel(list));
  await click('reader_toc'); await click('epub_toc_0');
  await wait(list => screenLabel(list).startsWith('1 / 3'));
  await pause(600);
  await theme('night');
  let list = ui.nodes();
  assert(list.some(n => n.type === 'image' && n.text === '蓝色山海与暖黄色月亮'));
  assert.equal(list.find(n => n.id === 'reader_top_bar').backgroundColor, '#FF252528');
  ui.screen('epub-illustrated-night');
  // The link lives in the publisher's body TOC, not the application's chapter sheet.
  ui.click('', '深入阅读');
  await wait(list => list.some(n => n.type === 'heading' && n.text === '深入阅读'));
  await pause(350);
  assert(screenLabel(ui.nodes()).startsWith('2 / 3'));
  ui.screen('epub-inline-anchor-verified');
  await theme('paper');
  list = ui.nodes();
  assert.equal(list.find(n => n.id === 'reader_top_bar').backgroundColor, '#FFF0E7D7');
  assert.equal(list.find(n => n.id === 'reader_bottom_bar').backgroundColor, '#FFF0E7D7');
  ui.screen('epub-illustrated-warm');
  await click('reader_settings');
  assert.equal(ui.nodes().find(n => n.id === 'reading_settings_panel').backgroundColor, '#FFF0E7D7', 'warm reading settings cannot inherit the white app background');
  assert.equal(ui.nodes().find(n => n.id === 'font_song').backgroundColor, '#FFF7F2E7', 'font cards use the same warm paper palette');
  ui.screen('reading-settings-warm-verified');
  await click('layout_single'); await click('reading_settings_close');
  await pause(400);
  assert(ui.nodes().some(n => n.id === 'epub_web'));
  await click('reader_settings'); await click('layout_double'); await click('reading_settings_close');
  await click('reader_toc'); await click('epub_toc_1'); await pause(700);
  const before = screenLabel(ui.nodes());
  const box = ui.bounds(ui.nodes().find(n => n.id === 'epub_web'));
  ui.run('shell', 'uitest', 'uiInput', 'click', String(box[2] - 70), String(Math.round((box[1] + box[3]) / 2)));
  await wait(list => screenLabel(list) !== before);
  const after = screenLabel(ui.nodes());
  ui.screen('epub-pagination');
  await click('reader_back'); await click('book_open_5');
  await wait(list => screenLabel(list) === after);
  await click('reader_back'); await click('tab_home');
  ui.screen('home-cover-palette');
  console.log(JSON.stringify({ inlineAnchor: true, pictures: true, nightAndWarmChrome: true, singleDouble: true, pageTurn: [before, after], progressRestored: true }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
