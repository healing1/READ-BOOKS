// Native emulator UI regression through Huawei's UI-test CLI (no browser or personal-device automation).
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const cli = process.env.HARMONYOS_CLI_HOME;
if (!cli) throw Error('Load scripts/harmony-env.ps1 first.');
const device = process.env.HDC_DEVICE;
if (!device || !/^127\.0\.0\.1:\d+$/.test(device)) throw Error('An explicit loopback emulator target is required.');
const hdc = path.join(cli, 'sdk/default/openharmony/toolchains/hdc.exe');
const out = path.join(__dirname, '../docs/qa');
const checks = [];
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const run = (...args) => execFileSync(hdc, ['-t', device, ...args], { encoding: 'utf8', windowsHide: true, timeout: 15000 });
const check = (condition, message) => { assert(condition, message); checks.push(message); };
function nodes() {
  run('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/reader-responsive.json');
  run('file', 'recv', '/data/local/tmp/reader-responsive.json', path.join(out, 'responsive-layout.json'));
  const items = [];
  function visit(node) { if (node.attributes?.visible === 'true') items.push(node.attributes); (node.children || []).forEach(visit); }
  visit(JSON.parse(fs.readFileSync(path.join(out, 'responsive-layout.json'), 'utf8')));
  return items;
}
function rect(node) {
  assert(node, 'Missing UI node');
  const [left, top, right, bottom] = node.bounds.match(/-?\d+/g).map(Number);
  return { left, top, right, bottom, width: right - left, height: bottom - top };
}
async function click(predicate) {
  const item = nodes().find(predicate);
  assert(item, 'Missing control: ' + predicate.toString());
  const b = rect(item);
  run('shell', 'uitest', 'uiInput', 'click', String(Math.round((b.left + b.right) / 2)), String(Math.round((b.top + b.bottom) / 2)));
  await pause(800);
}
async function tab(key) {
  let tree = nodes();
  if (tree.some(n => n.id === 'tab_' + key)) { await click(n => n.id === 'tab_' + key); }
  else {
    const label = { home: '主页', library: '书库', profile: '我的' }[key];
    const match = tree.filter(n => n.text === label).sort((a, b) => rect(b).bottom - rect(a).bottom)[0];
    assert(match, 'Missing native tab ' + key);
    await click(n => n.bounds === match.bounds && n.text === label);
  }
  tree = nodes();
  check(tree.some(n => n.id === 'page_' + key), 'visible page ' + key);
  const pill = tree.find(n => n.id === 'nav_selection');
  if (pill) {
    const a = rect(pill), b = rect(tree.find(n => n.id === 'tab_' + key));
    check(Math.abs(a.left - b.left) < 5 && Math.abs(a.right - b.right) < 5, 'aligned tab selection ' + key);
  }
}
async function capture(name) {
  await pause(300);
  run('shell', 'uitest', 'screenCap', '-p', '/data/local/tmp/reader-responsive.png');
  const file = path.join(out, 'verified-' + name + '.png');
  run('file', 'recv', '/data/local/tmp/reader-responsive.png', file);
  const png = fs.readFileSync(file);
  return { width: png.readUInt32BE(16), height: png.readUInt32BE(20) };
}
async function orient(mode) {
  const result = run('shell', 'aa', 'test', '-b', 'com.healing1.readbooks', '-m', 'entry_test',
    '-s', 'unittest', 'OrientationFixtureRunner', '-s', 'orientation', mode, '-s', 'timeout', '12000');
  assert(result.includes('ORIENTATION_OK:' + mode), 'Window orientation fixture failed: ' + result);
  await pause(1400);
}
async function appearance(label) {
  await tab('profile');
  await click(n => n.type === 'Text' && n.text === '外观');
  await click(n => n.id === 'sheet_action_' + label);
  await click(n => n.id === 'sheet_close');
}
async function main() {
  check(run('shell', 'param', 'get', 'const.product.model').trim().toLowerCase() === 'emulator', 'emulator-only guard');
  run('shell', 'aa', 'start', '-b', 'com.healing1.readbooks', '-a', 'EntryAbility');
  await pause(1000);
  await capture('initial');
  let initialAppearance = '深色';
  try {
    await tab('profile');
    const appearanceRow = nodes().find(n => n.text?.startsWith('外观, '));
    if (appearanceRow) initialAppearance = appearanceRow.text.split(', ')[1];
    await orient('landscape');
    await appearance('深色');
    await tab('home');
    let tree = nodes();
    const feature = rect(tree.find(n => n.id === 'home_featured'));
    const goal = rect(tree.find(n => n.id === 'home_goal_panel'));
    check(feature.right < goal.left && Math.abs(feature.top - goal.top) < 5, 'landscape home has two aligned columns');
    check(feature.width > goal.width, 'reading feature is wider than goal panel');
    await capture('landscape-home');
    for (const key of ['library', 'profile', 'home', 'library']) await tab(key);
    tree = nodes();
    check(tree.some(n => /^cover_image_/.test(n.id || '')), 'real image cover is mounted');
    check(tree.some(n => /^cover_text_/.test(n.id || '')), 'typeset fallback cover is mounted');
    await capture('landscape-library');
    await click(n => n.id === 'library_layout');
    await capture('landscape-library-list');
    await click(n => n.id === 'library_layout');
    await click(n => n.id === 'library_search_button');
    check(nodes().some(n => n.id === 'library_search'), 'search opens in library without being reset by tab sync');
    run('shell', 'uitest', 'uiInput', 'keyEvent', 'Back');
    await pause(700);
    await tab('profile');
    check(nodes().some(n => n.id === 'profile_wide_layout'), 'landscape profile uses two columns');
    await capture('landscape-profile');
    await appearance('浅色');
    await tab('home');
    await capture('landscape-home-light');
    await click(n => n.id === 'daily_goal');
    tree = nodes();
    check(tree.some(n => n.text === '每日阅读') && tree.some(n => n.text === '年度图书'), 'one goal sheet contains both settings');
    const close = rect(tree.find(n => n.id === 'sheet_close'));
    check(close.right < goal.right - 100, 'tablet sheet is centered and bounded');
    await capture('landscape-goals-light');
    await click(n => n.id === 'sheet_close');
    await appearance('深色');
    await tab('home');
    await orient('portrait');
    await tab('home');
    const portrait = await capture('portrait-size');
    check(portrait.width < portrait.height, 'portrait window is actually rotated');
    tree = nodes();
    check(!tree.some(n => n.id === 'home_wide_layout'), 'portrait home switches to stacked layout');
    check(rect(tree.find(n => n.id === 'home_featured')).width > 1500, 'portrait uses tablet width, not a phone-width panel');
    await capture('portrait-home');
    await tab('library'); await capture('portrait-library');
    await tab('profile'); await capture('portrait-profile');
  } finally {
    await orient('restore');
    await appearance(initialAppearance);
    await tab('home');
  }
  fs.writeFileSync(path.join(out, 'responsive-ui-tests.json'), JSON.stringify({ date: new Date().toISOString(), device,
    checks, result: 'PASS', note: 'Native HDS material and PDF Kit require a capable runtime; not asserted by this suite.' }, null, 2));
  console.log('Responsive native UI passed: ' + checks.length + ' checks; screenshots in docs/qa.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
