const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.HARMONY_TYPESCRIPT);
const source = fs.readFileSync(path.join(__dirname, '../read-books/entry/src/main/ets/theme/ShelfLayout.ets'), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
const result = { exports: {} };
new Function('exports', output)(result.exports);
const { ShelfLayout } = result.exports;
for (const [width, columns] of [[360, 2], [390, 2], [600, 3], [768, 4], [839, 4], [840, 4], [1000, 5], [1244, 6], [1440, 6], [2200, 6]]) {
  assert.equal(ShelfLayout.columns(width), columns, `columns at ${width}vp`);
}
for (let width = 320; width <= 2400; width += 8) {
  const count = ShelfLayout.columns(width);
  const available = ShelfLayout.contentWidth(width) - ShelfLayout.inset(width) * 2;
  const cover = (available - 24 * (count - 1)) / count;
  assert(cover >= 124 && cover <= 210, `${width}vp creates an unreasonable ${cover}vp cover`);
  if (width >= ShelfLayout.WIDE) {
    const goal = width >= 1100 ? 328 : 292;
    const feature = available - 24 - goal;
    const coverWidth = width >= 1100 ? 178 : 136;
    assert(feature - 64 - 28 - coverWidth >= 180, `${width}vp hero text is too narrow`);
  }
}
console.log('Shelf layout passed: 10 breakpoint expectations and 261 window-width checks.');
