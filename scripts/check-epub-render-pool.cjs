const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.HARMONY_TYPESCRIPT);
const root = path.join(__dirname, '../read-books/entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'reader/EpubRenderPool.ets'), 'utf8');
const out = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
const exportsObject = {}; new Function('exports', out)(exportsObject);
const pool = new exportsObject.EpubRenderPool();
const put = (id, index) => Object.assign(pool.slots[id], { path: `chapter-${index}`, index, ready: true, version: 1 });
put(0, 10); pool.current = 0; put(1, 11); put(2, 9);
assert.equal(pool.reserve('chapter-11', 11), 1, 'next chapter reuses its prepared surface');
assert.equal(pool.reserve('chapter-9', 9), 2, 'reverse turn reuses the previous surface');
pool.current = 1;
assert.equal(pool.reserve('chapter-12', 12), 3, 'use the fourth surface for a chapter two ahead');
put(3, 12);
pool.pending = 3;
assert.equal(pool.reserve('chapter-100', 100), 2, 'pending target cannot be recycled');
assert.notEqual(pool.reserve('chapter-11', 11), pool.current, 'same-chapter jump must not reload the visible Web');
pool.invalidate(); assert(pool.slots.every(s => !s.ready && s.version === -1));
const rolling = new exportsObject.EpubRenderPool();
const set = (id, index) => Object.assign(rolling.slots[id], { path: `chapter-${index}`, index, ready: true, version: 1 });
set(0, 10); set(1, 11); set(2, 12); set(3, 9); rolling.current = 0;
assert.equal(rolling.reserve('chapter-11', 11), 1);
assert.equal(rolling.reserve('chapter-12', 12), 2);
rolling.current = 1;
assert.equal(rolling.reserve('chapter-13', 13, ['chapter-10', 'chapter-12']), 3,
  'after one turn, recycle only the chapter two behind');
set(3, 13); rolling.current = 2;
assert.equal(rolling.reserve('chapter-14', 14, ['chapter-11', 'chapter-13']), 0,
  'two-ahead window rolls forward without evicting the immediate previous or next chapter');
rolling.current = 1; set(0, 10); set(1, 10); set(2, 11);
assert.equal(rolling.reserve('chapter-10', 10), 0, 'duplicate chapter jump reuses its nonvisible copy');
assert.equal(rolling.reserve('chapter-9', 9, ['chapter-11', 'chapter-13']), 0,
  'preparing the previous chapter must not evict the two prepared forward surfaces');
const reader = fs.readFileSync(path.join(root, 'pages/EpubReader.ets'), 'utf8');
assert.match(reader, /if \(\(!this\.hasPage && this\.busy\) \|\| this\.error\)/, 'regular handoff does not show a full-screen loading layer');
assert.match(reader, /renderMode: RenderMode\.ASYNC_RENDER/, 'full-screen EPUB uses a separate Web surface instead of synchronously repainting with ArkUI');
assert.match(reader, /this\.hasPage && this\.visibleSlot === id \? HitTestMode\.Default : HitTestMode\.None/, 'hidden neighbours never receive touches');
assert.match(reader, /if \(id !== this\.pool\.current\) \{ return true; \}/, 'background reports do not write reading progress');
assert.match(reader, /slot\.version !== this\.layoutVersion/, 'stale settings cannot activate an old prepared layout');
assert.match(reader, /index === this\.sectionIndex \+ 1 && this\.readyNeighbour\(1\) < 0/, 'distant chapters yield until the immediate next spread is ready');
assert.match(reader, /slot\.index === this\.sectionIndex \+ 1\) \{ this\.scheduleWarm\(\); \}/,
  'once the next spread is ready, its completion resumes two-ahead preparation');
assert.match(reader, /this\.outgoingSlot = prior/, 'the outgoing page remains opaque during handoff');
console.log('EPUB render pool passed: four-slot bound, rolling two-ahead prelayout, previous/next reuse, current/pending protection and no blank handoff layer.');
