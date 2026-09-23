const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.HARMONY_TYPESCRIPT);
const root = path.join(__dirname, '../read-books/entry/src/main');
const code = ts.transpileModule(fs.readFileSync(path.join(root, 'ets/reader/PageTurnMotion.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const out = {}; new Function('exports', code)(out);
const engine = fs.readFileSync(path.join(root, 'resources/rawfile/epub-engine.js'), 'utf8');
const jsPolicy = engine.slice(engine.indexOf('  function pageSettle('), engine.indexOf('  function handoffBody('));
const createJS = new Function('Date', 'pointerX', 'touch', jsPolicy + '\nreturn { pageSettle, sampleVelocity };');
let now = 0;
const state = { sampleX: 900, sampleTime: 0, movedAt: 0, velocity: 0 };
const js = createJS({ now: () => now }, p => p.x, state);
for (const span of [320, 768, 1244, 2800]) for (const fraction of [-1, -.8, -.2, 0, .01, .3, 1]) {
  for (const velocity of [null, -10, -1, 0, .2, 1, 10]) {
    const distance = span * fraction;
    const native = out.pageSettle(distance, span, velocity);
    assert.deepEqual({ ...native }, js.pageSettle(distance, span, velocity), 'ArkUI and ArkWeb share the same timing/curve');
    assert(native.duration === 0 || native.duration >= 160 && native.duration <= 320);
    assert(native.firstY >= 0 && native.firstY <= .4, 'gentler initial acceleration and monotonic bezier, no spring overshoot');
  }
}
assert(out.pageSettle(-800, 1000, -8).duration < out.pageSettle(-800, 1000, 0).duration);
assert(out.pageSettle(-100, 1000, 0).duration < out.pageSettle(-900, 1000, 0).duration);
assert.equal(out.pageSettle(0, 1000).duration, 0);
assert.equal(out.pageSettle(1000, 1000).duration, 320, 'a tap has enough visible travel instead of a short snap');
assert(out.pageSettle(-800, 1000, -100).duration >= 210, 'even an extreme flick cannot collapse most of a page into 80ms');
assert.match(engine, /cubic-bezier\(\.2,\$\{motion\.firstY\},\.55,1\)/);
const reader = fs.readFileSync(path.join(root, 'ets/pages/EpubReader.ets'), 'utf8');
assert.match(reader, /cubicBezierCurve\(0\.2, motion\.firstY, 0\.55, 1\)/);
assert(!reader.includes('setWebDebuggingAccess(true)'), 'temporary inspection access must not ship');
const nativeVelocity = new out.TurnVelocity(); nativeVelocity.start(900, 0);
for (const [time, x] of [[10, 880], [20, 840], [30, 800], [40, 820], [50, 830], [170, 830], [185, 850], [200, 880]]) {
  now = time; nativeVelocity.sample(x, time); js.sampleVelocity({ x });
  assert.equal(nativeVelocity.value, state.velocity);
  if (time === 40) assert(nativeVelocity.value > 0, 'reversal discards momentum in the old direction');
  if (time === 170) assert.equal(nativeVelocity.value, 0, 'pause before release cancels stale velocity');
}
console.log('Page-turn motion passed: ArkUI/ArkWeb parity, velocity-aware release, bounded duration, reversal, held-finger reset and no overshoot.');
