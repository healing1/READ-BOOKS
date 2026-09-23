const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../read-books/entry/src/main/ets/pages/Bookshelf.ets'), 'utf8');
const host = fs.readFileSync(path.join(__dirname, '../read-books/entry/src/main/ets/components/NativeShelfTabs.ets'), 'utf8');
assert.match(host, /@Component\s+export struct NativeShelfTabs/, 'API23/24 HDS must retain the verified ViewPU host');
assert.doesNotMatch(host, /@ComponentV2/, 'ViewV2 HDS host produced a blank root on the API24 tablet');
assert.match(host, /@Prop\s+@Watch\('selectedChanged'\)/, 'native tab state must still update from its V2 parent');
assert.match(host, /enableComponentSafeArea:\s*true/, 'the floating HDS title bar must not cover the first content row');
for (const key of ['home', 'library', 'profile']) {
  assert.match(host, new RegExp('this\\.' + key + 'Scroller'), 'each tab must bind its own stable Scroll controller');
}
// A source-level regression guard for the API24 startup crash. A bare BuilderParam
// method gets the child as `this`; invoke the actual arrow callback with that receiver.
// Reference: Huawei arkts-builderparam, "this" / arrow-function parameter binding.
for (const page of ['home', 'library', 'profile']) {
  const match = source.match(new RegExp(page + ':\\s*(\\(\\)\\s*=>\\s*\\{\\s*this\\.' + page + 'Page\\(\\);?\\s*\\})'));
  assert(match, page + ' BuilderParam must preserve its Bookshelf owner');
  const owner = { tabPage: key => key, [page + 'Page']() { return this.tabPage(page); } };
  let called = false;
  owner.tabPage = key => { assert.equal(key, page); called = true; };
  const callback = new Function('return ' + match[1]).call(owner);
  assert.doesNotThrow(() => callback.call({}), page + ' must not read tabPage from NativeShelfTabs');
  assert(called, page + ' must reach its parent builder');
}
console.log('Native page builders passed: parent context, API24 host compatibility and per-tab scroll binding.');
