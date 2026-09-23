const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.HARMONY_TYPESCRIPT);
require.extensions['.ets'] = (module, file) => module._compile(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, file);
const root = path.join(__dirname, '../read-books/entry/src/main/ets');
const { Chapter } = require(path.join(root, 'model/Models.ets'));
const { EpubContentsLinks, ContentsHit } = require(path.join(root, 'reader/EpubContentsLinks.ets'));
const { PaginationCore } = require(path.join(root, 'reader/PaginationCore.ets'));
const chapter = (idx, title, offset) => Object.assign(new Chapter(), { idx, title, startOffset: offset });
const toc = chapter(0, '目录', 100);
const targets = [chapter(1, '第一章 海上的故事', 1000), chapter(2, '第二章 远方', 2000), chapter(3, '第三章 回家', 3000)];
const resolver = new EpubContentsLinks([toc, ...targets]);
const body = '目录\n\n第一章 海上的故事\n第二章 远方……12\n第三章 回家\n';
const links = resolver.resolve(toc, body);
assert.deepEqual(links.map(l => l.target), [1000, 2000, 3000]);
assert.equal(body.substring(links[0].start - 100, links[0].end - 100), '第一章 海上的故事');
assert.equal(resolver.resolve(chapter(7, '正文', 100), body.replace('目录\n', '')).length, 0, 'ordinary prose is not a TOC');
assert.equal(resolver.resolve(chapter(7, '章节4', 100), body.replace('目录\n', '')).length, 3, 'legacy unnamed contents spine');
assert.equal(resolver.resolve(toc, '第一章 海上的故事还有更多内容\n').length, 0, 'no partial-label guessing');
const ambiguous = new EpubContentsLinks([...targets, chapter(9, targets[0].title, 9000)]);
assert.equal(ambiguous.resolve(toc, targets[0].title).length, 0, 'duplicate labels must not jump to an arbitrary chapter');
const continuation = new EpubContentsLinks([...targets, chapter(9, targets[0].title + '（续 2）', 9000)]);
assert.equal(continuation.resolve(toc, targets[0].title)[0].target, 1000, 'large chapter continuation retains its original target');
for (const width of [100, 200, 360, 700]) for (const font of [17, 26]) {
  const pages = PaginationCore.paginate(body, 0, 100, { widthPx: width, heightPx: 180, padLeftPx: 12, padRightPx: 12,
    padTopPx: 20, padBottomPx: 20, fontSizePx: font, lineHeightRatio: 1.55 }, { measure: () => font });
  const lines = pages.flatMap(p => p.lines);
  for (const line of lines) assert.equal(line.text.replace(/^　　/, ''), body.substring(line.startOffset - 100, line.endOffset - 100));
  for (const link of links) assert(lines.some(line => line.startOffset < link.end && line.endOffset > link.start), 'wrapped TOC link lost during reflow');
}
const hit = new ContentsHit(600, 100, 200, 40, links[0]);
assert(hit.contains(650, 110)); assert(!hit.contains(50, 110)); assert(!hit.contains(650, 141));
console.log('EPUB inline contents: exact/legacy/dotted labels, ambiguous/non-TOC rejection, eight reflows, UTF-16 line anchors and spread hit regions passed.');
