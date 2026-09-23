// Bounded startup smoke test. Requires an explicitly authorized HDC target;
// does not import books, change preferences, clear data, or change orientation.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const device = process.env.HDC_DEVICE;
assert(device && process.env.DEVECO_SDK_HOME, 'Load harmony-env.ps1 and explicitly set HDC_DEVICE.');
const hdc = path.join(process.env.DEVECO_SDK_HOME, 'default/openharmony/toolchains/hdc.exe');
const qa = path.join(__dirname, '../docs/qa');
const run = (...args) => execFileSync(hdc, ['-t', device, ...args], { encoding: 'utf8', windowsHide: true, timeout: 10000 });
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
function nodes() {
  run('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/readbooks-startup.json');
  // HDC Windows accepts native backslash absolute paths, not C:/... paths.
  const local = path.join(qa, 'startup-layout.json');
  run('file', 'recv', '/data/local/tmp/readbooks-startup.json', local);
  const root = JSON.parse(fs.readFileSync(local, 'utf8'));
  const app = (root.children || []).find(n => n.attributes?.bundleName === 'com.healing1.readbooks');
  assert(app, 'Reader is not the visible window; unlock it and open the reader first.');
  const items = [];
  function visit(n) { if (n.attributes) items.push(n.attributes); (n.children || []).forEach(visit); }
  visit(app);
  return items;
}
function bounds(n) { assert(n, 'Missing node'); return n.bounds.match(/-?\d+/g).map(Number); }
async function main() {
  const checks = [];
  for (const [key, label] of [['library', '书库'], ['profile', '我的'], ['home', '主页']]) {
    const items = nodes();
    assert(items.some(n => n.id === 'native_shelf_navigation'), 'HDS navigation did not attach to the window.');
    const tab = items.filter(n => n.text === label && n.type === 'Column')
      .sort((a, b) => bounds(b)[3] - bounds(a)[3])[0];
    const b = bounds(tab);
    run('shell', 'uitest', 'uiInput', 'click', String(Math.round((b[0] + b[2]) / 2)), String(Math.round((b[1] + b[3]) / 2)));
    await pause(700);
    const after = nodes();
    const page = after.find(n => n.id === 'page_' + key);
    const title = after.find(n => n.id === 'HdsTitleBar');
    assert(page, key + ' page is blank');
    assert(bounds(page)[1] >= bounds(title)[3] - 2, key + ' content overlaps the native title bar');
    checks.push(key + ': rendered content below native title bar');
  }
  run('shell', 'uitest', 'screenCap', '-p', '/data/local/tmp/readbooks-startup.png');
  run('file', 'recv', '/data/local/tmp/readbooks-startup.png', path.join(qa, 'pad-restored-home.png'));
  const pid = run('shell', 'pidof', 'com.healing1.readbooks').trim();
  assert(/^\d+$/.test(pid), 'Reader is no longer running.');
  fs.writeFileSync(path.join(qa, 'startup-smoke.json'), JSON.stringify({ date: new Date().toISOString(),
    result: 'PASS', checks, scope: 'Startup and three HDS tabs only; not full visual, format or material acceptance.' }, null, 2));
  console.log(checks.join('\n') + '\nStartup smoke passed. Reader PID: ' + pid);
}
main().catch(e => { console.error(e); process.exitCode = 1; });
