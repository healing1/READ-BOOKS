const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const ts = require(process.env.HARMONY_TYPESCRIPT);
const source = fs.readFileSync(path.join(__dirname, '../read-books/entry/src/main/ets/reader/ReadingSession.ets'), 'utf8');
const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
const intervals = [];
let now = 1000000;
let finishWrite;
const exported = {};
const context = { exports: exported, Date: { now: () => now },
  require: () => ({ ReadingActivityRepo: { recordInterval: (start, end) => {
    intervals.push([start, end]);
    return new Promise((resolve) => { finishWrite = resolve; });
  } } }) };
vm.runInNewContext(code, context);
async function main() {
  const session = new exported.ReadingSession();
  session.resume();
  now += 10000;
  const paused = session.pause();
  session.resume();
  finishWrite();
  await paused;
  now += 10000;
  const resumed = session.flush();
  finishWrite();
  await resumed;
  assert.equal(intervals.length, 2, 'A slow pause must not overwrite a newer resume');
  assert.deepEqual(intervals, [[1000000, 1010000], [1010000, 1020000]]);
  now += 3600000;
  const delayed = session.flush();
  finishWrite();
  await delayed;
  assert.equal(intervals[2][1] - intervals[2][0], 35000, 'Suspended timers cannot add background hours');
  const stopped = session.pause();
  await stopped;
  now += 10000;
  await session.flush();
  assert.equal(intervals.length, 3);
  console.log('Reading session: pause/resume race, foreground accounting, suspension cap and stopped timer passed.');
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
