const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const ts = require(process.env.HARMONY_TYPESCRIPT);
const root = path.join(__dirname, '../read-books/entry/src/main');
function compile(file, deps = {}) {
  const source = fs.readFileSync(path.join(root, 'ets', file + '.ets'), 'utf8').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const out = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const exports = {};
  new Function('require', 'exports', out)(name => { assert(name in deps, name); return deps[name]; }, exports);
  return exports;
}
let persisted, failSave = false, saves = 0;
const kit = { PersistenceV2: { connect: (type, key, factory) => persisted || factory(), save() { saves++; if (failSave) throw Error('disk full'); } } };
const { ReadingSettings } = compile('model/ReadingSettings', { '@kit.ArkUI': kit });
const { ReadingFonts } = compile('reader/ReadingFonts');
const removed = [];
const registered = [];
const { ReadingAssets } = compile('reader/ReadingAssets', { '@kit.ArkUI': kit,
  '@kit.ArkGraphics2D': { text: { FontCollection: { getGlobalInstance: () => ({ loadFontSync: (...args) => registered.push(args) }) } } },
  '@kit.CoreFileKit': { fileIo: { accessSync: () => true, unlink: async file => removed.push(file) } }, './CoverStore': {} });
persisted = new ReadingSettings();
assert.equal(ReadingSettings.load().fontChoice, 'default');
persisted = Object.assign(new ReadingSettings(), { fontPath: '/app/files/custom.font', fontFamily: 'CustomFace', fontName: 'My Font' });
assert.equal(ReadingSettings.load().fontChoice, 'custom', 'existing imported fonts survive migration');
const original = [persisted.fontPath, persisted.fontFamily, persisted.fontName];
ReadingAssets.register({}, persisted); ReadingAssets.register({}, persisted);
assert.deepEqual(registered, [['CustomFace', 'file:///app/files/custom.font']], 'Canvas custom fonts register synchronously once per family');
for (const [choice, family, request] of [['song', 'ReadBooksSong', '__reader_song__.otf'], ['kai', 'ReadBooksKai', '__reader_kai__.ttf'],
  ['default', 'sans-serif', ''], ['custom', 'CustomFace', '__reader_font__?v=CustomFace']]) {
  ReadingAssets.selectFont(persisted, choice);
  assert.equal(ReadingSettings.load().fontChoice, choice, 'explicit choice survives reload even with a saved custom font');
  assert.equal(ReadingFonts.family(persisted), family); assert.equal(ReadingFonts.request(persisted), request);
  assert.deepEqual([persisted.fontPath, persisted.fontFamily, persisted.fontName], original);
}
failSave = true;
assert.throws(() => ReadingAssets.selectFont(persisted, 'song'));
assert.equal(persisted.fontChoice, 'custom', 'failed persistence rolls back selection');
failSave = false;
assert.throws(() => ReadingAssets.selectFont(persisted, '../fonts/not-allowed'));
persisted = Object.assign(new ReadingSettings(), { fontChoice: 'custom' });
assert.equal(ReadingSettings.load().fontChoice, 'default');
assert.throws(() => ReadingAssets.selectFont(persisted, 'custom'));
for (const unknown of ['__reader_bad__.ttf', '../fonts/LXGWWenKai-Regular.ttf', 'fonts/LXGWWenKai-Regular.ttf']) {
  assert.equal(ReadingFonts.resource(unknown), '', 'built-in resource loader is an exact allowlist');
}
// Check original font identities, sfnt tables and Chinese glyphs without a platform font fallback.
function glyph(font, cmap, code) {
  const count = font.readUInt16BE(cmap + 2);
  for (let i = 0; i < count; i++) {
    const sub = cmap + font.readUInt32BE(cmap + 4 + i * 8 + 4), format = font.readUInt16BE(sub);
    if (format === 12) {
      const groups = font.readUInt32BE(sub + 12);
      for (let g = 0; g < groups; g++) {
        const off = sub + 16 + g * 12, start = font.readUInt32BE(off), end = font.readUInt32BE(off + 4);
        if (code >= start && code <= end) return font.readUInt32BE(off + 8) + code - start;
      }
    }
    if (format === 4 && code < 65536) {
      const segments = font.readUInt16BE(sub + 6) / 2, ends = sub + 14, starts = ends + segments * 2 + 2;
      const deltas = starts + segments * 2, ranges = deltas + segments * 2;
      for (let s = 0; s < segments; s++) if (code >= font.readUInt16BE(starts + s * 2) && code <= font.readUInt16BE(ends + s * 2)) {
        const delta = font.readInt16BE(deltas + s * 2), range = font.readUInt16BE(ranges + s * 2);
        if (!range) return (code + delta) & 65535;
        const index = font.readUInt16BE(ranges + s * 2 + range + 2 * (code - font.readUInt16BE(starts + s * 2)));
        return index ? (index + delta) & 65535 : 0;
      }
    }
  }
  return 0;
}
for (const [name, signature, identity, license] of [
  ['SourceHanSerifSC-Regular.otf', 0x4f54544f, 'cb41635674be23029e98469f729eded6ebc54611', 'SourceHanSerif-OFL.txt'],
  ['LXGWWenKai-Regular.ttf', 0x00010000, '39ad71264b588165b469e35e6afb162a378dacd1f95348160240ba9038ac3009', 'LXGWWenKai-OFL.txt']]) {
  const font = fs.readFileSync(path.join(root, 'resources/rawfile/fonts', name));
  assert.equal(font.readUInt32BE(0), signature);
  const hash = identity.length === 40 ? crypto.createHash('sha1').update(Buffer.from('blob ' + font.length + '\0')).update(font).digest('hex') : crypto.createHash('sha256').update(font).digest('hex');
  assert.equal(hash, identity, 'must bundle the unmodified official release');
  let cmap = -1;
  for (let i = 0; i < font.readUInt16BE(4); i++) {
    const off = 12 + i * 16, begin = font.readUInt32BE(off + 8), size = font.readUInt32BE(off + 12);
    assert(begin + size <= font.length);
    if (font.toString('ascii', off, off + 4) === 'cmap') cmap = begin;
  }
  assert(cmap >= 0);
  for (const char of '阅读宋体楷体绍宋第一章明道宫春江花月夜，。！？') assert(glyph(font, cmap, char.codePointAt(0)) > 0, name + ' missing ' + char);
  assert.match(fs.readFileSync(path.join(root, 'resources/rawfile/fonts', license), 'utf8'), /SIL OPEN FONT LICENSE Version 1\.1/);
}
async function resetChecks() {
  const settings = Object.assign(new ReadingSettings(), { fontChoice: 'song', fontPath: '/app/reading_assets/ReaderCustom_1_0.font',
    fontFamily: 'CustomFace', fontName: 'MyFont', backgroundPath: '/app/my-background.png' });
  const ui = { getHostContext: () => ({ filesDir: '/app' }) };
  failSave = true;
  await assert.rejects(ReadingAssets.reset(ui, settings, true));
  assert.equal(settings.fontPath, '/app/reading_assets/ReaderCustom_1_0.font'); assert.equal(settings.fontChoice, 'song');
  assert.equal(settings.backgroundPath, '/app/my-background.png'); assert.equal(removed.length, 0);
  failSave = false;
  await ReadingAssets.reset(ui, settings, true);
  assert.equal(settings.fontChoice, 'song'); assert.equal(settings.fontPath, '');
  assert.equal(settings.backgroundPath, '/app/my-background.png', 'removing a stored custom font must not remove the background');
  assert.deepEqual(removed, ['/app/reading_assets/ReaderCustom_1_0.font']);
  console.log('Reading fonts passed: original binaries, Chinese glyphs, license bundling, migration, choices, custom asset preservation, isolated removal and rollback.');
}
resetChecks().catch(error => { console.error(error); process.exitCode = 1; });
