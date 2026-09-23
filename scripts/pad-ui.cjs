// Explicit-target, app-scoped UI helper. Never follows system windows or unlocks devices.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const device = process.env.HDC_DEVICE;
assert(device && process.env.DEVECO_SDK_HOME, 'Set an explicitly authorized HDC_DEVICE.');
const hdc = path.join(process.env.DEVECO_SDK_HOME, 'default/openharmony/toolchains/hdc.exe');
const qa = path.join(__dirname, '../docs/qa');
const run = (...args) => {
  const result = execFileSync(hdc, ['-t', device, ...args], { encoding: 'utf8', windowsHide: true, timeout: 10000 });
  // HDC can report a disconnected explicit target with exit code zero. Never reuse an old UI dump.
  assert(!/^\[(?:Fail|F)\]/m.test(result), result);
  return result;
};
function nodes() {
  run('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/readbooks-refinement.json');
  const local = path.join(qa, 'refinement-layout-' + device.replace(/[^a-zA-Z0-9-]/g, '-') + '.json');
  run('file', 'recv', '/data/local/tmp/readbooks-refinement.json', local);
  const root = JSON.parse(fs.readFileSync(local, 'utf8'));
  const app = root.children?.find(n => n.attributes?.bundleName === 'com.healing1.readbooks');
  assert(app, 'Reader is not visible. Unlock and open it; no system window will be operated.');
  const items = [];
  (function visit(n) {
    if (n.attributes) items.push(n.attributes);
    // UITest still enumerates opaque-zero ArkWeb descendants despite the native
    // accessibility guard. Hidden preload links/headings cannot prove visible UI.
    if (n.attributes?.id?.startsWith('epub_prepared_')) return;
    (n.children || []).forEach(visit);
  })(app);
  return items;
}
function bounds(n) { assert(n, 'Requested app control is not present'); return n.bounds.match(/-?\d+/g).map(Number); }
function click(id, text) {
  const items = nodes();
  const matches = items.filter(n => id ? n.id === id : n.text === text);
  const node = matches.find(n => n.type === 'Button') || matches.find(n => n.type === 'Column') || matches[0];
  const b = bounds(node);
  assert(b[2] > b[0] && b[3] > b[1] && node.enabled !== 'false', 'Control is not enabled or laid out');
  run('shell', 'uitest', 'uiInput', 'click', String(Math.round((b[0] + b[2]) / 2)), String(Math.round((b[1] + b[3]) / 2)));
}
function screen(name) {
  assert(/^[a-z0-9-]+$/.test(name));
  nodes();
  run('shell', 'uitest', 'screenCap', '-p', '/data/local/tmp/readbooks-refinement.png');
  run('file', 'recv', '/data/local/tmp/readbooks-refinement.png', path.join(qa, name + '.png'));
}
async function leaveReader() {
  const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
  let items = nodes();
  const reader = items.find(n => n.id === 'epub_web' || n.id === 'reader_canvas');
  if (!reader) return;
  if (!items.some(n => n.id === 'reader_back')) {
    const b = bounds(reader);
    run('shell', 'uitest', 'uiInput', 'click', String(Math.round((b[0] + b[2]) / 2)), String(Math.round((b[1] + b[3]) / 2)));
    await pause(400);
  }
  click('reader_back');
  for (let attempt = 0; attempt < 20; attempt++) {
    await pause(150);
    if (nodes().some(n => n.id === 'tab_library')) return;
  }
  throw Error('Reader did not return to the shelf');
}
if (require.main === module) {
  const [action, value] = process.argv.slice(2);
  if (action === 'click') click(value);
  else if (action === 'text') click('', value);
  else if (action === 'screen') screen(value);
  else console.log(JSON.stringify(nodes().filter(n => n.id || ['Button', 'Search', 'TextInput', 'SheetPage'].includes(n.type))
    .map(n => ({ id: n.id, type: n.type, text: n.text, description: n.description, bounds: n.bounds, color: n.backgroundColor })), null, 2));
}
module.exports = { run, nodes, click, bounds, screen, leaveReader };
