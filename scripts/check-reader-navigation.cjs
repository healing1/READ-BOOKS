const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const compilerPath = process.env.HARMONY_TYPESCRIPT;
if (!compilerPath) {
  throw new Error('Set HARMONY_TYPESCRIPT to the HarmonyOS toolchain typescript.js path.');
}
const ts = require(compilerPath);
require.extensions['.ets'] = (module, file) => {
  const source = fs.readFileSync(file, 'utf8');
  const result = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  });
  module._compile(result.outputText, file);
};

const sourceRoot = path.join(__dirname, '../read-books/entry/src/main/ets');
const { Page } = require(path.join(sourceRoot, 'model/Models.ets'));
const { PageCursor, PageNavigation } = require(path.join(sourceRoot, 'reader/PageNavigation.ets'));

async function main() {
  let comparisons = 0;
  for (const counts of [[1], [1, 1], [1, 1, 1, 1, 1], [3, 1, 4, 2]]) {
    const flat = counts.flatMap((count, chapterIdx) =>
      Array.from({ length: count }, (_, pageIdx) => ({ chapterIdx, pageIdx })));
    const pages = counts.map((count, chapterIdx) =>
      Array.from({ length: count }, (_, index) => new Page(chapterIdx, index, index + 1, [])));
    for (let index = 0; index < flat.length; index++) {
      for (const spread of [false, true]) {
        for (const direction of [-1, 1]) {
          const entry = flat[index];
          const actual = await PageNavigation.turn(new PageCursor(entry.chapterIdx, entry.pageIdx),
            direction, spread, counts.length, async (chapterIdx) => pages[chapterIdx]);
          const targetIndex = index + direction * (spread ? 2 : 1);
          const expected = targetIndex >= 0 && targetIndex < flat.length ? flat[targetIndex] :
            direction < 0 && index === 1 && spread ? flat[0] : null;
          assert.deepEqual(actual === null ? null : {
            chapterIdx: actual.chapterIdx, pageIdx: actual.pageIdx
          }, expected);
          comparisons++;
        }
      }
    }
  }
  await assert.rejects(() => PageNavigation.turn(new PageCursor(0, 0), 1, false, 2,
    async (index) => index === 0 ? [new Page(0, 0, 1, [])] : []));
  console.log(`Reader navigation: ${comparisons} boundary/spread cases and failed-chapter propagation passed.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
