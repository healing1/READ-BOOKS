// Emulator-only sustained chapter-turn regression. No personal Pad data is touched.
const assert = require('node:assert/strict');
const ui = require('./pad-ui.cjs');
assert.match(process.env.HDC_DEVICE, /^127\.0\.0\.1:\d+$/);
assert.equal(ui.run('shell', 'param', 'get', 'const.product.model').trim(), 'emulator');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const status = () => ui.nodes().find(n => n.type === 'Text' && /章 · .*屏/.test(n.text))?.text || '';

async function main() {
  ui.run('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', 'com.healing1.readbooks');
  await pause(1000); await ui.leaveReader();
  ui.click('tab_library'); await pause(350); ui.click('book_open_7'); await pause(1200);
  ui.click('reader_toc'); await pause(350); ui.click('epub_toc_4'); await pause(800);
  const initial = ui.nodes(), before = status();
  assert.match(before, /^6 \/ 445 章 · 1 \/ \d+ 屏$/);
  const box = ui.bounds(initial.find(item => item.id === 'epub_web'));
  const y = Math.round((box[1] + box[3]) / 2);
  const right = box[2] - 160, left = box[0] + 160;
  const started = new Date();
  const pad = value => String(value).padStart(2, '0');
  const mark = `${pad(started.getMonth() + 1)}-${pad(started.getDate())} ${pad(started.getHours())}:${pad(started.getMinutes())}:${pad(started.getSeconds())}.${String(started.getMilliseconds()).padStart(3, '0')}`;
  const freshLogs = () => ui.run('shell', 'hilog', '-x', '-T', 'ReadBooksEpubPerf').split(/\r?\n/)
    .filter(line => line.slice(0, 18) >= mark).join('\n');
  let after = before, inputs = 0, logs = '';
  for (let burst = 0; burst < 22; burst++) {
    for (let n = 0; n < 5; n++) {
      ui.run('shell', 'uitest', 'uiInput', 'swipe', String(right), String(y), String(left), String(y), '15000');
      inputs++;
    }
    await pause(120);
    after = status();
    logs += freshLogs();
    if (Number(after.match(/^(\d+) \/ 445 章/)?.[1] || 0) >= 11) break;
  }
  assert(Number(after.match(/^(\d+) \/ 445 章/)?.[1] || 0) >= 11,
    `sustained touches must pass at least five chapter boundaries: ${after}`);
  logs += freshLogs();
  if (logs.includes('coldBoundary=')) {
    const lines = logs.split('\n'); const at = lines.findIndex(line => line.includes('coldBoundary='));
    const chapterStart = lines.findLastIndex((line, index) => index < at && line.includes('chapter=7 readyMs='));
    assert.fail('a page reached a chapter before its neighbouring layout was ready: ' +
      lines.slice(Math.max(0, chapterStart < 0 ? at - 50 : chapterStart), at + 5).join('\n'));
  }
  await ui.leaveReader();
  console.log(JSON.stringify({ before, after, inputs,
    warmed: (logs.match(/warmChapter=/g) || []).length, coldBoundaries: 0 }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
