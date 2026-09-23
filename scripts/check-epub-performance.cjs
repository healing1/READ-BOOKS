const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.HARMONY_TYPESCRIPT);
const root = path.join(__dirname, '../read-books/entry/src/main/ets/reader');
function compile(file) {
  const source = fs.readFileSync(path.join(root, file + '.ets'), 'utf8');
  const out = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const exports = {}; new Function('require', 'exports', out)(() => ({}), exports); return exports;
}
const { EpubResourceCache } = compile('EpubResourceCache');
const cache = new EpubResourceCache(10, 3);
cache.put('a', new Uint8Array(4)); cache.put('b', new Uint8Array(4)); cache.get('a');
cache.put('c', new Uint8Array(4));
assert.equal(cache.get('b'), undefined); assert(cache.get('a')); assert.equal(cache.sizeBytes(), 8);
cache.put('a', new Uint8Array(2)); assert.equal(cache.sizeBytes(), 6);
cache.put('huge', new Uint8Array(11)); assert.equal(cache.get('huge'), undefined); assert.equal(cache.sizeBytes(), 6);
cache.put('empty-1', new Uint8Array()); cache.put('empty-2', new Uint8Array());
assert.equal(cache.get('c'), undefined, 'entry count is bounded even for tiny or empty files');
cache.clear(); assert.equal(cache.sizeBytes(), 0); assert.equal(cache.get('a'), undefined);
const { epubCrc32 } = compile('EpubArchive');
assert.equal(epubCrc32(new TextEncoder().encode('123456789')), 0xcbf43926);
assert.equal(epubCrc32(new Uint8Array()), 0);
function reference(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) { value ^= byte; for (let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0); }
  return (value ^ 0xffffffff) >>> 0;
}
for (const length of [1, 255, 4097, 1024 * 1024]) {
  const bytes = Uint8Array.from({ length }, (_, i) => (i * 113 + (i >>> 8)) & 255);
  assert.equal(epubCrc32(bytes), reference(bytes), 'fast CRC must retain corruption checks');
}
console.log('EPUB performance passed: bounded per-book LRU, eviction/replacement/release, oversized-entry rejection and table CRC parity.');
