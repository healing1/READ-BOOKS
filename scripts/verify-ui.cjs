const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const cli = process.env.HARMONYOS_CLI_HOME;
if (!cli) throw new Error('Load scripts/harmony-env.ps1 first.');
const hdc = path.join(cli, 'sdk/default/openharmony/toolchains/hdc.exe');
const out = path.join(__dirname, '../docs/qa');
const prefix = process.argv[2] || 'tablet';
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const run = (...args) => execFileSync(hdc, process.env.HDC_DEVICE ? ['-t', process.env.HDC_DEVICE, ...args] : args,
  { encoding: 'utf8', windowsHide: true });

function nodes() {
  run('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/readbooks-ui.json');
  run('file', 'recv', '/data/local/tmp/readbooks-ui.json', path.join(out, 'ui-layout.json'));
  const result = [];
  function visit(node) {
    if (node.attributes) result.push(node.attributes);
    for (const child of node.children || []) visit(child);
  }
  visit(JSON.parse(fs.readFileSync(path.join(out, 'ui-layout.json'), 'utf8')));
  return result;
}

function bounds(node) {
  const value = node.bounds.match(/\d+/g).map(Number);
  return { x: Math.round((value[0] + value[2]) / 2), y: Math.round((value[1] + value[3]) / 2),
    width: value[2] - value[0], height: value[3] - value[1] };
}

async function click(predicate) {
  const node = nodes().find((node) => node.visible === 'true' && predicate(node));
  assert(node, 'Expected visible control was not found');
  const point = bounds(node);
  run('shell', 'uitest', 'uiInput', 'click', String(point.x), String(point.y));
  await pause(450);
}

async function capture(name) {
  await pause(300);
  run('shell', 'snapshot_display', '-f', '/data/local/tmp/readbooks-ui.jpeg');
  run('file', 'recv', '/data/local/tmp/readbooks-ui.jpeg', path.join(out, `${prefix}-${name}.jpeg`));
}

async function main() {
  run('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', 'com.healing1.readbooks');
  await pause(800);
  await click((node) => node.id === 'tab_home');
  assert(nodes().some((node) => node.id === 'daily_goal'));
  await capture('home');
  await click((node) => node.id === 'tab_library');
  assert(nodes().some((node) => node.id === 'library_more'));
  await capture('library');
  await click((node) => node.id === 'library_layout');
  await capture('library-list');
  await click((node) => node.id === 'library_layout');
  await click((node) => node.id === 'nav_search');
  const search = nodes().find((node) => node.id === 'library_search');
  assert(search);
  const point = bounds(search);
  run('shell', 'uitest', 'uiInput', 'inputText', String(point.x), String(point.y), 'NO_MATCH_READBOOKS_QA');
  await pause(450);
  assert(nodes().some((node) => node.text === '没有找到相关图书'));
  run('shell', 'uitest', 'uiInput', 'keyEvent', 'Back');
  await pause(250);
  await capture('search');
  await click((node) => node.id === 'tab_profile');
  assert(nodes().some((node) => node.text === '我的阅读'));
  await capture('profile');
  await click((node) => node.text === '阅读目标');
  assert(nodes().some((node) => node.text === '每日阅读'));
  await capture('goals');
  await click((node) => node.id === 'sheet_close');
  await click((node) => node.id === 'tab_home');
  console.log(`UI flows passed (${prefix}): three tabs, grid/list, search empty state, profile, goal sheet.`);
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
