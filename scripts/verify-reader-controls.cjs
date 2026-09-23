// Run only while the user has handed over the Pad and opened Reading Settings.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ui = require('./pad-ui.cjs');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function main() {
  const initial = ui.nodes();
  const find = (items, id) => items.find(n => n.id === id);
  const font = Number(find(initial, 'reader_font_value')?.text);
  const line = Number(find(initial, 'reader_line_value')?.text);
  assert(Number.isFinite(font) && Number.isFinite(line), 'Open the reading settings first');
  const sheet = initial.find(n => n.type === 'SheetPage').bounds;
  const canvas = find(initial, 'reader_canvas').bounds;
  const layout = initial.find(n => /^layout_(single|double)$/.test(n.id) && n.backgroundColor !== '#00000000')?.id;
  assert(!initial.some(n => n.id === 'layout_auto'), 'Automatic layout option must be removed');
  assert(layout, 'Cannot determine the current layout; do not change it');
  const fontUp = font < 26;
  const lineUp = line < 2;
  const checks = [];
  let fontChanged = false, lineChanged = false, layoutChanged = false;
  try {
    ui.click(fontUp ? 'reader_font_plus' : 'reader_font_minus'); fontChanged = true;
    await pause(150);
    const afterFont = ui.nodes();
    assert.equal(Number(find(afterFont, 'reader_font_value').text), font + (fontUp ? 1 : -1));
    assert(!afterFont.some(n => /正在排版/.test(n.text)), 'Reflow must not mount the full-screen loading overlay');
    ui.click(lineUp ? 'reader_line_plus' : 'reader_line_minus'); lineChanged = true;
    await pause(150);
    assert.equal(Number(find(ui.nodes(), 'reader_line_value').text), Number((line + (lineUp ? 0.05 : -0.05)).toFixed(2)));
    checks.push('font and line-height feedback updates without reopening; no full-screen reflow mask');
    for (const id of ['layout_single', 'layout_double']) {
      ui.click(id); layoutChanged = true;
      await pause(150);
      const items = ui.nodes();
      assert.notEqual(find(items, id).backgroundColor, '#00000000', id + ' did not show selection');
      for (const other of ['layout_single', 'layout_double'].filter(k => k !== id)) {
        assert.equal(find(items, other).backgroundColor, '#00000000', other + ' kept stale selection');
      }
      assert.equal(items.find(n => n.type === 'SheetPage').bounds, sheet, 'Sheet jumped during layout selection');
      assert.equal(find(items, 'reader_canvas').bounds, canvas, 'Canvas resized during layout selection');
    }
    checks.push('single/double selections update immediately; no auto option; sheet and canvas keep their bounds');
  } finally {
    if (layoutChanged) ui.click(layout);
    if (fontChanged) ui.click(fontUp ? 'reader_font_minus' : 'reader_font_plus');
    if (lineChanged) ui.click(lineUp ? 'reader_line_minus' : 'reader_line_plus');
  }
  const restored = ui.nodes();
  assert.equal(Number(find(restored, 'reader_font_value').text), font);
  assert.equal(Number(find(restored, 'reader_line_value').text), line);
  assert.notEqual(find(restored, layout).backgroundColor, '#00000000');
  fs.writeFileSync(path.join(__dirname, '../docs/qa/reader-controls-smoke.json'), JSON.stringify({ date: new Date().toISOString(), result: 'PASS', checks, settingsRestored: true }, null, 2));
  console.log(checks.join('\n') + '\nOriginal font, line-height and layout restored.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
