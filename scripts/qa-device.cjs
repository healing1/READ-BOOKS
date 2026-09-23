// Read-only inspection and explicit UI actions for the connected reader QA emulator.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const hdc = path.join(process.env.DEVECO_SDK_HOME, 'default/openharmony/toolchains/hdc.exe');
const output = path.join(__dirname, '../docs/qa');
const run = (...args) => execFileSync(hdc, ['-t', process.env.HDC_DEVICE || '127.0.0.1:5555', ...args],
  { encoding: 'utf8', windowsHide: true });
const [action = 'nodes', value = 'h6-current'] = process.argv.slice(2);
if (action === 'capture') {
  if (!/^[a-z0-9_-]+$/i.test(value)) throw new Error('Invalid screenshot name');
  run('shell', 'uitest', 'screenCap', '-p', '/data/local/tmp/reader-qa.png');
  run('file', 'recv', '/data/local/tmp/reader-qa.png', path.join(output, value + '.png'));
  console.log(path.join(output, value + '.png'));
} else {
  run('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/reader-qa.json');
  const local = path.join(output, 'h6-layout.json');
  run('file', 'recv', '/data/local/tmp/reader-qa.json', local);
  const nodes = [];
  const visit = n => { if (n.attributes) nodes.push(n.attributes); (n.children || []).forEach(visit); };
  visit(JSON.parse(fs.readFileSync(local, 'utf8')));
  if (action === 'nodes') console.log(JSON.stringify(nodes.filter(n => n.visible === 'true' && (n.text || n.id))
    .map(n => ({ id: n.id, text: n.text, bounds: n.bounds, type: n.type })), null, 2));
  else {
    const node = nodes.find(n => n.visible === 'true' && (action === 'id' ? n.id === value : n.text === value));
    if (!node) throw new Error('Control not found: ' + value);
    const b = node.bounds.match(/-?\d+/g).map(Number);
    console.log(run('shell', 'uitest', 'uiInput', 'click', String(Math.round((b[0] + b[2]) / 2)),
      String(Math.round((b[1] + b[3]) / 2))));
  }
}
