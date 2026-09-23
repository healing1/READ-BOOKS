const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.HARMONY_TYPESCRIPT);
const root = path.join(__dirname, '../read-books/entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'theme/ReadingRefresh.ets'), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
let info = { refreshRate: 60, supportedRefreshRates: [30, 60, 90, 120] }, throws = false;
let started = 0, stopped = 0, unsubscribed = 0, frame, requested, frames = 0, nextTimer = 0;
const timers = new Map();
const sync = { on(type, callback) { frame = callback; }, off() { unsubscribed++; },
  setExpectedFrameRateRange(value) { requested = value; }, start() { started++; }, stop() { stopped++; } };
const exportsObject = {};
new Function('require', 'exports', 'setTimeout', 'clearTimeout', compiled)(name => name === '@kit.ArkUI' ?
  { display: { getDefaultDisplaySync() { if (throws) throw Error('no display'); return info; } } } :
  { displaySync: { create: () => sync } }, exportsObject,
  callback => { timers.set(++nextTimer, callback); return nextTimer; }, id => timers.delete(id));
const { ReadingRefresh, readingFrameRange } = exportsObject;
for (const rate of [30, 60, 90, 120, 144, 165]) {
  assert.deepEqual(readingFrameRange(rate), { min: 0, max: rate, expected: rate });
}
assert.deepEqual(readingFrameRange(60, [0, NaN, -1, 90, 120]), { min: 0, max: 120, expected: 120 });
assert.deepEqual(readingFrameRange(NaN, []), { min: 0, max: 0, expected: 0 }, 'unknown display follows system, not guessed 120');
const refresh = new ReadingRefresh(() => frames++);
refresh.begin(false); assert(refresh.running); assert.equal(requested.expected, 120);
for (let i = 0; i < 200; i++) refresh.begin(false);
assert.equal(started, 1, 'moving does not recreate/restart the vsync subscription');
frame(); assert.equal(frames, 1);
refresh.end(); assert.equal(timers.size, 1);
refresh.begin(false); assert.equal(timers.size, 0, 'next touch cancels the old idle timeout');
refresh.end(); for (const callback of [...timers.values()]) callback();
assert(!refresh.running); assert.equal(timers.size, 0); frame(); assert.equal(frames, 1, 'no idle rendering');
info = { refreshRate: 90 };
refresh.begin(false); assert.equal(requested.expected, 90, 're-read active display at next interaction');
refresh.begin(true); assert(!refresh.running, 'respect reduced motion');
throws = true; assert.deepEqual(ReadingRefresh.range(), { min: 0, max: 0, expected: 0 });
refresh.dispose(); assert.equal(unsubscribed, 1); assert(stopped > 0);
const reader = fs.readFileSync(path.join(root, 'pages/EpubReader.ets'), 'utf8');
assert.match(reader, /padding\(\{ left: 0, right: 0, top: 84, bottom: 120 \}\)/, 'full-width Web can draw across the former native gutters');
assert.match(reader, /config\.gutter = this\.wide \? 48 : 24/, 'retain the original resting text margins inside the Web');
assert(!reader.includes('pendingDragOffset'), 'native touch input must not wait for a second vsync callback');
assert.match(reader, /this\.dragOffset = this\.drag\.offset/); assert.match(reader, /refresh\.dispose\(\)/);
assert.match(reader, /expectedFrameRateRange:.*ReadingRefresh\.range\(\)/);
console.log('Reading refresh passed: display-supported 30–165 Hz, no invented cap, direct touch delivery, idle cleanup, reduced motion and full-width EPUB drawing with original resting margins.');
