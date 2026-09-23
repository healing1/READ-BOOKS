const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.HARMONY_TYPESCRIPT);
const root = path.join(__dirname, '../read-books/entry/src/main/ets');
function source(file) { return fs.readFileSync(path.join(root, file + '.ets'), 'utf8'); }
function compile(file, dependencies = {}) {
  const text = source(file).replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const output = ts.transpileModule(text, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const result = {};
  new Function('require', 'exports', output)(name => {
    assert(name in dependencies, 'Unmocked dependency: ' + name);
    return dependencies[name];
  }, result);
  return result;
}
const models = compile('model/Models');
const { BookSelection } = compile('reader/BookSelection', { '../model/Models': models });
const { ThemeManager: theme } = compile('theme/ThemeManager');
let persisted;
const persistence = { PersistenceV2: { connect: (type, key, factory) => persisted ?? factory() } };
const { AppPreferences } = compile('model/AppPreferences', { '@kit.ArkUI': persistence });
const { ReadingSettings } = compile('model/ReadingSettings', { '@kit.ArkUI': persistence });
function book(id, createdAt, lastReadAt = 0, title = 'Book ' + id) {
  return Object.assign(new models.Book(), { id, createdAt, lastReadAt, title });
}
const seed = book(1, 1, 1000, '示例 · 西游记（节选）');
const first = book(2, 20, 0);
const latest = book(3, 30, 0);
const opened = book(4, 25, 50);
const books = [seed, first, latest, opened];
const snapshot = JSON.stringify(books);
assert.equal(BookSelection.featured([], []).id, 0);
assert.equal(BookSelection.featured([seed], []).id, 1);
assert.equal(BookSelection.featured([seed, first, latest], []).id, 3, 'new import supersedes the seed');
assert.equal(BookSelection.featured(books, []).id, 4, 'opening at offset zero counts as reading');
assert.equal(BookSelection.featured(books, [4]).id, 3, 'finished book is not a continue-reading candidate');
assert.deepEqual(BookSelection.suggestions(books, 4).map(b => b.id), [3, 2, 1]);
assert.equal(BookSelection.suggestions(Array.from({ length: 30 }, (_, i) => book(i, i)), -1).length, 10);
assert.equal(JSON.stringify(books), snapshot, 'selection must not mutate the library');
for (const app of ['dark', 'light', 'system']) for (const systemDark of [false, true]) {
  assert.equal(theme.resolve('system', systemDark, app).bg,
    app === 'dark' || (app === 'system' && systemDark) ? theme.NIGHT.bg : theme.WHITE.bg);
  for (const key of ['night', 'paper', 'white']) {
    assert.equal(theme.resolve(key, systemDark, app), theme[key.toUpperCase()], 'explicit paper overrides app appearance');
    assert.equal(theme.chromeDark(key, systemDark, app), key === 'night', 'toolbar must obey explicit paper/night selection');
  }
}
assert.equal(AppPreferences.cleanName('  小明\n  '), '小明');
assert.equal(AppPreferences.cleanName('  '), '书友');
assert.equal(AppPreferences.cleanName(undefined), '书友');
assert.equal(AppPreferences.cleanName('a'.repeat(30)).length, 20);
persisted = Object.assign(new ReadingSettings(), { pageMode: 'tap', theme: 'system' });
assert.equal(ReadingSettings.load().pageMode, 'both');
persisted.pageMode = 'slide';
assert.equal(ReadingSettings.load().pageMode, 'both');
persisted.layoutMode = 'auto';
assert.equal(ReadingSettings.load().layoutMode, 'double', 'migrate legacy automatic layout');
const reader = source('pages/Reader');
assert.doesNotMatch(reader, /settings\.pageMode/, 'both gestures are always enabled');
assert.match(reader, /ThemeManager\.resolve\(this\.settings\.theme, this\.isDark, this\.preferences\.appearance\)/);
assert.match(reader, /WithTheme\(\{ colorMode: this\.chromeMode\(\) \}\)/);
assert.doesNotMatch(source('components/ReadingSettingsPanel'), /layout_auto|label: '自动'/);
assert.doesNotMatch(source('pages/PdfReader'), /pdf-auto|label: '自动'/);
assert.match(reader, /this\.busy && this\.pages\.length === 0/, 'no full-screen loading mask during reflow');
assert.match(reader, /preferType: this\.wideWindow/, 'sheet geometry cannot depend on single/double selection');
assert.match(reader, /maxWidth: this\.wideWindow \? READER_SPREAD_MAX_WIDTH/, 'single/double cannot resize and clear the canvas');
assert.doesNotMatch(source('components/ReadingSettingsPanel'), /翻页方式|onMode/);
assert.match(source('components/ReadingSettingsPanel'), /@Param selected: boolean/);
assert.match(source('components/ReadingContentsPanel'), /onDataReloaded/);
for (const file of ['Reader', 'PdfReader']) {
  const s = source('pages/' + file);
  const back = s.slice(s.indexOf('private async backToShelf'), s.indexOf('\n  }', s.indexOf('private async backToShelf')));
  assert(back.indexOf('await this.leaveImmersiveMode()') > 0);
  assert(back.indexOf('await this.leaveImmersiveMode()') < back.indexOf('router.back()'));
}
for (const file of ['Reader', 'PdfReader', 'EpubReader']) {
  const s = source('pages/' + file);
  const appear = s.slice(s.indexOf('aboutToAppear()'), s.indexOf('onPageShow()'));
  assert.doesNotMatch(appear, /this\.(enterImmersiveMode|immersive)\(/,
    'must not resize the still-visible shelf during reader creation');
  assert.match(s, /PageTransitionEnter\([\s\S]*?progress >= 1[\s\S]*?this\.(enterImmersiveMode|immersive)\(/);
  assert.match(s, /PageTransitionEnter\(ReaderMotion.pageEnter[\s\S]*?\.opacity\([\s\S]*?\.translate\([\s\S]*?\.scale\(/,
    'a duration/callback without a visible animation effect is insufficient');
}
assert.match(reader, /!this\.immersiveReady \|\| this\.leaving/);
assert.match(reader, /this\.firstFramePublished \? delay : Math\.max\(80, delay\)/);
assert.match(reader, /\.opacity\(this\.paperOpacity\)/);
assert.match(source('pages/Bookshelf'), /current\.format === 'epub' && !current\.sourcePath[\s\S]*?选择原文件/);
assert.match(source('pages/Bookshelf'), /book\.format === 'epub' \? 'pages\/EpubReader'/);
assert.match(source('pages/Bookshelf'), /SuggestedBook\(/);
assert.match(source('components/SuggestedBook'), /aspectRatio\(this\.ratio\)/);
assert.match(source('components/BookCover'), /!this\.imageFailed \? Color\.Transparent : this\.tone\(\)/);
assert.doesNotMatch(source('pages/Bookshelf'), /getRawFileContent\('sample.txt'\)/, 'new installations stay empty');
async function main() {
  for (const failure of ['', 'write', 'persist']) {
    const directory = '/app/files/profile';
    const old = directory + '/avatar_1.png';
    const files = new Set([directory, old, 'picker://original.png']);
    const removed = [];
    let closed = false, synced = false;
    const fakeFs = {
      OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
      accessSync: file => files.has(file), mkdirSync: file => files.add(file),
      async open(file) { files.add(file); return { fd: 9 }; },
      async write(fd, buffer) { if (failure === 'write') throw Error('disk full'); return Math.min(4096, buffer.byteLength); },
      async fsync() { synced = true; }, async close() { closed = true; },
      async rename(from, to) { assert(files.has(from)); files.delete(from); files.add(to); },
      async unlink(file) { removed.push(file); files.delete(file); }
    };
    const { ProfileStore } = compile('reader/ProfileStore', {
      '@kit.CoreFileKit': { fileIo: fakeFs }, '@kit.ArkUI': { PersistenceV2: { save() { if (failure === 'persist') throw Error('persistence failed'); } } },
      '../reader/CoverStore': {}, './CoverStore': { CoverStore: { async readImage(uri) { assert.equal(uri, 'picker://original.png'); return new Uint8Array(20000); } } }
    });
    const profile = { avatarPath: old };
    if (failure) {
      await assert.rejects(ProfileStore.replaceAvatar({ filesDir: '/app/files' }, 'picker://original.png', profile));
      assert.equal(profile.avatarPath, old);
      assert(files.has(old));
      assert.equal(files.size, 3, 'failed copy must not leak temporary/new avatars');
    } else {
      await ProfileStore.replaceAvatar({ filesDir: '/app/files' }, 'picker://original.png', profile);
      assert.notEqual(profile.avatarPath, old);
      assert(files.has(profile.avatarPath));
      assert(synced);
      assert(!files.has(old));
    }
    assert(closed);
    assert(!removed.includes('picker://original.png'), 'never touch the selected original image');
  }
  const { WindowMode } = compile('utils/WindowMode', { '@kit.ArkUI': {} });
  const order = [];
  const win = {
    async setWindowLayoutFullScreen(value) { await Promise.resolve(); order.push('full:' + value); },
    async setWindowSystemBarEnable(value) { await Promise.resolve(); order.push('bars:' + value.join(',')); }
  };
  await Promise.all([WindowMode.setReaderMode(win, true), WindowMode.setReaderMode(win, false), WindowMode.setReaderMode(win, true)]);
  assert.deepEqual(order, ['full:true', 'bars:', 'bars:status,navigation', 'full:false', 'full:true', 'bars:']);
  console.log('Reading refinements passed: book selection, 24 appearance/theme combinations, profile validation and write/rollback safety, gesture migration, reflow/sheet guards and window ordering.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
