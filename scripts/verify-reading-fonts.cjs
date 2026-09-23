const assert = require('node:assert/strict');
const ui = require('./pad-ui.cjs');
assert.match(process.env.HDC_DEVICE, /^127\.0\.0\.1:\d+$/, 'Diagnostic fixtures must stay on the emulator');
assert.equal(ui.run('shell', 'param', 'get', 'const.product.model').trim(), 'emulator');
const pause = ms => new Promise(r => setTimeout(r, ms));
async function click(id) { ui.click(id); await pause(450); }
async function hud() {
  if (ui.nodes().some(n => n.id === 'reader_back')) return;
  const b = ui.bounds(ui.nodes().find(n => n.id === 'reader_canvas' || n.id === 'epub_web'));
  ui.run('shell', 'uitest', 'uiInput', 'click', String((b[0] + b[2]) / 2), String((b[1] + b[3]) / 2));
  await pause(450);
}
async function choose(font) {
  await click('reader_settings'); await click('font_' + font); await pause(850);
  if (font === 'song') ui.screen('builtin-font-picker');
  await click('reading_settings_close'); await pause(600);
}
async function main() {
  if (ui.nodes().some(n => n.id === 'reader_canvas' || n.id === 'epub_web')) await hud();
  if (ui.nodes().some(n => n.id === 'reader_back')) await click('reader_back');
  await click('tab_library'); await click('book_open_7'); await pause(1800);
  await click('reader_toc'); await click('epub_toc_4'); await pause(850);
  for (const face of ['song', 'kai']) {
    await choose(face);
    assert(ui.nodes().some(n => n.type === 'image' && n.text === 'chapter-head'));
    ui.screen('shaosong-builtin-' + face);
  }
  await click('reader_back'); await click('book_open_4'); await pause(1000);
  ui.screen('txt-builtin-kai'); await hud(); await choose('song');
  ui.screen('txt-builtin-song'); await click('reader_back');
  ui.run('shell', 'aa', 'force-stop', 'com.healing1.readbooks');
  ui.run('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', 'com.healing1.readbooks'); await pause(1800);
  await click('tab_library'); await click('book_open_4'); await pause(1000);
  ui.screen('txt-builtin-song-restarted'); await hud(); await choose('default');
  await click('reader_back'); await click('tab_home');
  console.log('Built-in font UI: EPUB and TXT Song/Kai screenshots captured, images retained, Song restart captured, default restored. Inspect screenshots for real glyph styles.');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
