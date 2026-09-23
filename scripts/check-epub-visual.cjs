const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.HARMONY_TYPESCRIPT);
const vm = require('node:vm');
const root = path.join(__dirname, '../read-books/entry/src/main/ets');
function compile(file, deps = {}) {
  const source = fs.readFileSync(path.join(root, file + '.ets'), 'utf8').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const out = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const exports = {};
  new Function('require', 'exports', out)(name => { assert(name in deps, name); return deps[name]; }, exports);
  return exports;
}
const { CoverColors } = compile('theme/CoverColors');
const solid = new Uint8Array(32 * 32 * 4);
for (let i = 0; i < solid.length; i += 4) solid.set([30, 94, 125, 255], i);
assert.equal(CoverColors.dominant(solid, '#123456'), '#105070'); // quantized dominant bin
assert.equal(CoverColors.dominant(new Uint8Array(4096), '#123456'), '#123456');
for (const dark of [false, true]) for (const end of [false, true]) {
  assert.match(CoverColors.surface('#1e5e7d', dark, end), /^#[a-f\d]{6}$/i);
  assert.notEqual(CoverColors.surface('#1e5e7d', dark, end), CoverColors.surface('#da4030', dark, end));
}
const kit = { util: { TextDecoder: { create: () => ({ decodeToString: b => new TextDecoder().decode(b) }) } } };
const archiveModule = compile('reader/EpubArchive', { '@kit.CoreFileKit': {}, '@kit.ArkTS': kit, '@kit.BasicServicesKit': {} });
const readingFonts = compile('reader/ReadingFonts');
const resourceCache = compile('reader/EpubResourceCache');
const res = compile('reader/EpubResources', { '@kit.CoreFileKit': {}, '@kit.ArkTS': kit,
  './EpubArchive': archiveModule, './EpubDocument': {}, './ReadingFonts': readingFonts, './EpubResourceCache': resourceCache,
  './EpubFonts': { EpubFonts: class { decode(path, bytes) { return bytes; } } } });
assert.equal(res.epubRequestPath(res.epubUrl('OPS/山 海.xhtml', 'a')), 'OPS/山 海.xhtml');
const bookOrigin = 'https://book-1-1.readbooks.invalid/';
assert.equal(res.epubRequestPath(res.epubUrl('OPS/one.xhtml', 'heading', bookOrigin), bookOrigin), 'OPS/one.xhtml');
assert.throws(() => res.epubRequestPath(res.epubUrl('OPS/one.xhtml', '', bookOrigin), 'https://book-1-2.readbooks.invalid/'), 'cached resources are isolated between books');
for (const url of ['https://example.com/image.png', 'file:///etc/passwd', 'javascript:alert(1)',
  'https://readbooks.invalid.evil/x', 'https://readbooks.invalid/%2e%2e/x', 'https://readbooks.invalid/%5cetc']) {
  assert.throws(() => res.epubRequestPath(url));
}
global.WebResourceResponse = class {
  setResponseIsReady(v) { this.ready = v; } setResponseCode(v) { this.code = v; }
  setReasonMessage(v) {} setResponseEncoding(v) {} setResponseHeader(v) { this.headers = v; }
  setResponseData(v) { this.data = v; } setResponseMimeType(v) { this.mime = v; }
};
async function main() {
  // A deliberately lagging CSS transform reproduces Back during a page-turn animation.
  const engine = fs.readFileSync(path.join(root, '../resources/rawfile/epub-engine.js'), 'utf8');
  const colorFunctions = engine.slice(engine.indexOf('  function neutralColor('), engine.indexOf('  function readingRect('));
  const inkNodes = [
    { tagName: 'P', color: 'rgb(0, 0, 0)', backgroundColor: 'rgba(0, 0, 0, 0)' },
    { tagName: 'H2', color: 'rgb(255, 144, 0)', backgroundColor: 'rgba(0, 0, 0, 0)' },
    { tagName: 'IMG', color: 'rgb(0, 0, 0)', backgroundColor: 'rgb(255, 255, 255)' }
  ].map(node => Object.assign(node, { attrs: new Set(), closest: () => null,
    setAttribute(name) { this.attrs.add(name); }, removeAttribute(name) { this.attrs.delete(name); } }));
  const applyInk = new Function('body', 'getComputedStyle', colorFunctions + '\nreturn themeInk;')(
    { querySelectorAll: () => inkNodes }, node => node);
  applyInk({ text: '#DADADD', dark: true });
  assert(inkNodes[0].attrs.has('data-readbooks-neutral-ink'));
  assert(!inkNodes[1].attrs.has('data-readbooks-neutral-ink'), 'preserve the original gold chapter ornament');
  assert.equal(inkNodes[2].attrs.size, 0, 'never recolor an illustration');
  function engineHarness(positions = [0, 1048, 2096], images = [], author = {}, textContent, decodeBackground) {
    let clockOffset = 0;
    const listeners = {};
    const input = {}, metrics = { rects: 0, styles: 0, queries: 0 }, messages = [], frames = [];
    let hidden = true;
    const body = { style: {}, scrollWidth: 3143, textContent: textContent ?? 'A normal text chapter with more than thirty characters.', querySelector: () => null, addEventListener() {} };
    const injectedStyle = {};
    const translation = () => body.style.transition?.startsWith('transform') ? 0 :
      Number((body.style.transform?.match(/translate3d\(([-\d.]+)px,0,0\)/) || [0, 0])[1]);
    const nodes = positions.map((_, i) => ({ getBoundingClientRect() {
      metrics.rects++;
      const x = positions[i];
      return { left: x + translation(), right: x + translation() + 400, top: 10, bottom: 300, width: 400, height: 290 };
    } }));
    body.querySelectorAll = selector => { metrics.queries++; return selector.startsWith('p,') ? nodes : []; };
    const context = { window: {}, document: { body, documentElement: { style: {} }, createElement: () => injectedStyle, head: { appendChild() {} },
      images, getElementById: () => ({ remove() { hidden = false; } }),
      addEventListener(name, callback) { input[name] = callback; } }, innerWidth: 1000, innerHeight: 700,
      getSelection: () => ({ toString: () => '' }),
      getComputedStyle: () => { metrics.styles++; return { transform: String(translation()), direction: 'ltr', writingMode: 'horizontal-tb', ...author }; },
      Image: class { decode() { return decodeBackground ? decodeBackground(this.src) : Promise.resolve(); } },
      DOMMatrixReadOnly: class { constructor(value) { this.m41 = Number(value); this.m42 = 0; } },
      requestAnimationFrame: callback => frames.push(callback), Date: { now: () => Date.now() + clockOffset },
      console: { info(message) { messages.push(JSON.parse(message.substring(2))); } }, addEventListener(name, callback) { listeners[name] = callback; }, setTimeout, clearTimeout };
    vm.runInNewContext(engine, context);
    context.window.ReadBooks.testResize = () => listeners.resize();
    context.window.ReadBooks.testMetrics = () => ({ ...metrics });
    context.window.ReadBooks.testInput = input;
    context.window.ReadBooks.testBody = body;
    context.window.ReadBooks.testMessages = messages;
    context.window.ReadBooks.testFrames = frames;
    context.window.ReadBooks.testHidden = () => hidden;
    context.window.ReadBooks.testStyle = injectedStyle;
    context.window.ReadBooks.testHtmlStyle = context.document.documentElement.style;
    context.window.ReadBooks.testAdvanceTime = ms => { clockOffset += ms; };
    return context.window.ReadBooks;
  }
  const config = { token: 'QA', spread: true, publisher: true, bg: '#fff', text: '#000' };
  const guttered = engineHarness(); guttered.layout({ ...config, gutter: 48 });
  assert.match(guttered.testStyle.textContent, /left:48px!important/);
  assert.match(guttered.testStyle.textContent, /width:904px!important/, 'same 48 px margins and text width as the old inset Web');
  assert.equal(guttered.testHtmlStyle.clipPath, 'inset(0px 48px)');
  guttered.testInput.touchstart({ touches: [{ clientX: 800, clientY: 200 }] });
  const gutterMetrics = guttered.testMetrics();
  guttered.testInput.touchmove({ touches: [{ clientX: 700, clientY: 200 }], preventDefault() {} });
  assert.equal(guttered.testHtmlStyle.clipPath, 'inset(0px 0px)', 'dragged text is clipped at screen edge, not at the resting margin');
  assert.deepEqual(guttered.testMetrics(), gutterMetrics, 'opening the edges must not reflow or remeasure');
  guttered.testAdvanceTime(5000);
  guttered.testInput.touchend({ changedTouches: [{ clientX: 700, clientY: 200 }] });
  assert.equal(JSON.parse(guttered.state()).page, 1, 'a deliberate slow held swipe still commits after 1.2 seconds');
  assert.equal(guttered.testHtmlStyle.clipPath, 'inset(0px 0px)', 'release animation keeps the edges open');
  guttered.testInput.touchstart({ touches: [{ clientX: 500, clientY: 200 }] });
  guttered.testInput.touchend({ changedTouches: [{ clientX: 500, clientY: 200 }] });
  await new Promise(resolve => setTimeout(resolve, 390));
  assert.equal(guttered.testHtmlStyle.clipPath, 'inset(0px 48px)', 'a fresh tap cannot leave neighbouring-column fragments exposed after settling');
  const coverPage = engineHarness(undefined, [], { backgroundImage: 'url("https://book.readbooks.invalid/portrait.jpg")', backgroundSize: 'cover' }, ' \u00a0 ');
  coverPage.layout({ ...config, warm: true });
  assert.match(coverPage.testStyle.textContent, /background-size:contain!important/);
  assert.match(coverPage.testStyle.textContent, /background-attachment:scroll!important/);
  assert.match(coverPage.testStyle.textContent, /column-count:auto!important/, 'picture-only frontmatter uses the full Pad viewport, not half a spread');
  // Two background URL references (body/html) share the same deferred decoder in this harness.
  let finishDecode;
  const decodeWait = new Promise(resolve => { finishDecode = resolve; });
  const warmPage = engineHarness(undefined, [], { backgroundImage: 'url("portrait.jpg")', backgroundSize: 'cover' }, '', () => decodeWait);
  warmPage.prepare({ ...config, warm: true }, null);
  await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
  assert(warmPage.testHidden()); assert.equal(warmPage.testFrames.length, 0, 'background art must decode before readiness');
  finishDecode();
  for (let i = 0; i < 8; i++) await Promise.resolve();
  assert.equal(warmPage.testFrames.length, 1);
  warmPage.testFrames.shift()(); warmPage.testFrames.shift()(); await Promise.resolve();
  assert(!warmPage.testHidden()); assert.equal(warmPage.testMessages.at(-1).type, 'ready');
  let releaseOld;
  const oldDecode = new Promise(resolve => { releaseOld = resolve; });
  const superseded = engineHarness(undefined, [], { backgroundImage: 'url("portrait.jpg")' }, '', () => oldDecode);
  superseded.prepare({ ...config, warm: true }, null);
  for (let i = 0; i < 5; i++) await Promise.resolve();
  superseded.prepare({ ...config, token: 'QB' }, null);
  for (let i = 0; i < 5; i++) await Promise.resolve();
  superseded.testFrames.shift()(); superseded.testFrames.shift()(); await Promise.resolve();
  const readyCount = superseded.testMessages.filter(m => m.type === 'ready').length;
  releaseOld(); for (let i = 0; i < 8; i++) await Promise.resolve();
  assert.equal(superseded.testMessages.filter(m => m.type === 'ready').length, readyCount, 'superseded background decode cannot publish a stale layout');
  const turning = engineHarness(); turning.layout(config); turning.go(1);
  const measured = turning.testMetrics();
  for (let turn = 0; turn < 100; turn++) { turning.go(-1); turning.go(1); }
  assert.deepEqual(turning.testMetrics(), measured, '200 rapid turns require no DOM queries, geometry reads or computed-style reads');
  const destination = JSON.parse(turning.state());
  assert.equal(destination.page, 1); assert.equal(destination.locator.element, 1, 'save destination before the animation finishes');
  const reopened = engineHarness(); reopened.layout(config, destination.locator);
  assert.equal(JSON.parse(reopened.state()).page, 1, 'reopen must not fall back one spread');
  const dragging = engineHarness(); dragging.layout(config);
  const nativeEdge = engineHarness(); nativeEdge.layout({ ...config, nativeBoundary: true }); nativeEdge.go(2); nativeEdge.testAdvanceTime(400);
  const nativeEdgeTransform = nativeEdge.testBody.style.transform;
  const nativeMetrics = nativeEdge.testMetrics();
  nativeEdge.testInput.touchstart({ touches: [{ screenX: 900, screenY: 200, clientX: 800, clientY: 200 }] });
  nativeEdge.testInput.touchmove({ touches: [{ screenX: 400, screenY: 202, clientX: 800, clientY: 202 }], preventDefault() {} });
  assert.equal(nativeEdge.testBody.style.transform, nativeEdgeTransform, 'native chapter drag must not also move the body or expose an empty document edge');
  const boundaryReports = nativeEdge.testMessages.filter(m => m.type === 'turn').length;
  nativeEdge.testInput.touchend({ changedTouches: [{ screenX: 400, screenY: 202, clientX: 800, clientY: 202 }] });
  assert.equal(nativeEdge.testMessages.filter(m => m.type === 'turn').length, boundaryReports, 'native release owns the chapter commit, no duplicate JS turn');
  assert.equal(nativeEdge.testMetrics().rects, nativeMetrics.rects, 'no per-move layout measurement');
  nativeEdge.testInput.touchstart({ touches: [{ screenX: 900, screenY: 200 }] });
  nativeEdge.testInput.touchend({ changedTouches: [{ screenX: 880, screenY: 200 }] });
  let cancelledClick = false;
  nativeEdge.testInput.click({ clientX: 880, target: {}, preventDefault() { cancelledClick = true; } });
  assert(cancelledClick, 'a short cancelled boundary drag without touchmove must not become a click-turn');
  assert.equal(nativeEdge.testMessages.filter(m => m.type === 'turn').length, boundaryReports);
  const interruptedEdge = engineHarness(); interruptedEdge.layout({ ...config, nativeBoundary: true }); interruptedEdge.go(2);
  interruptedEdge.testInput.touchstart({ touches: [{ clientX: 900, clientY: 200 }] });
  assert.equal(interruptedEdge.testBody.style.transform, 'translate3d(0px,0,0)');
  interruptedEdge.testInput.touchmove({ touches: [{ clientX: 870, clientY: 200 }], preventDefault() {} });
  assert.equal(interruptedEdge.testBody.style.transform, 'translate3d(-2096px,0,0)', 'an interrupted chapter-edge drag resumes the in-chapter remainder, never strands the body mid-spread');
  assert.match(interruptedEdge.testBody.style.transition, /^transform /);
  interruptedEdge.testInput.touchend({ changedTouches: [{ clientX: 880, clientY: 200 }] });
  assert.equal(interruptedEdge.testMessages.filter(m => m.type === 'turn').length, 0, 'native short-drag cancellation still owns the chapter decision');
  const held = engineHarness(); held.layout(config); held.holdInput(true);
  const heldBefore = held.state();
  held.testInput.touchstart({ touches: [{ clientX: 900, clientY: 200 }] });
  held.testInput.touchmove({ touches: [{ clientX: 300, clientY: 200 }], preventDefault() {} });
  held.testInput.touchend({ changedTouches: [{ clientX: 300, clientY: 200 }] });
  let heldClick = false; held.testInput.click({ clientX: 900, preventDefault() { heldClick = true; } });
  assert.equal(held.state(), heldBefore); assert(heldClick, 'outgoing Web cannot duplicate a root-owned followup turn');
  held.holdInput(false); held.go(1);
  assert.equal(JSON.parse(held.state()).page, 1, 'activation restores input and accepts exactly the retained turn');
  dragging.testInput.touchstart({ touches: [{ clientX: 800, clientY: 200 }] });
  let prevented = false;
  dragging.testInput.touchmove({ touches: [{ clientX: 710, clientY: 202 }], preventDefault() { prevented = true; } });
  assert(prevented); assert.equal(dragging.testBody.style.transform, 'translate3d(-90px,0,0)', 'paper follows finger before touchend');
  dragging.testInput.touchend({ changedTouches: [{ clientX: 710, clientY: 202 }] });
  assert.equal(JSON.parse(dragging.state()).page, 1);
  let preventedSynthetic = false;
  dragging.testInput.click({ preventDefault() { preventedSynthetic = true; } });
  assert(preventedSynthetic, 'the swipe-generated click must not turn a second page');
  dragging.testInput.touchstart({ touches: [{ clientX: 800, clientY: 200 }] });
  assert.equal(dragging.testBody.style.transition, 'none', 'new contact freezes the previous animation immediately, not on the first move');
  assert.equal(dragging.testBody.style.transform, 'translate3d(0px,0,0)', 'freeze exactly at the presentation position returned by the mock compositor');
  dragging.testInput.touchmove({ touches: [{ clientX: 710, clientY: 202 }], preventDefault() {} });
  assert.equal(dragging.testBody.style.transform, 'translate3d(-90px,0,0)', 'a second gesture picks up the visible transition, not its distant target');
  dragging.testInput.touchcancel();
  dragging.testInput.touchstart({ touches: [{ clientX: 900, clientY: 200 }] });
  dragging.testInput.touchend({ changedTouches: [{ clientX: 900, clientY: 200 }] });
  dragging.testInput.click({ clientX: 900, target: {}, preventDefault() { throw Error('fresh tap must not be suppressed for 500 ms'); } });
  assert.equal(JSON.parse(dragging.state()).page, 2, 'a fresh tap immediately after a swipe is accepted');
  dragging.go(-1);
  dragging.go(3);
  assert.deepEqual(dragging.testMessages.at(-1), { type: 'turn', delta: 1, carry: 1 }, 'retain excess fast turns across a chapter boundary');
  const idleDrag = engineHarness(); idleDrag.layout(config);
  const beforeIdleContact = idleDrag.testMetrics();
  idleDrag.testInput.touchstart({ touches: [{ clientX: 800, clientY: 200 }] });
  assert.deepEqual(idleDrag.testMetrics(), beforeIdleContact, 'at rest there is no computed-style read on contact');
  idleDrag.testAdvanceTime(20);
  idleDrag.testInput.touchmove({ touches: [{ clientX: 700, clientY: 200 }], preventDefault() {} });
  idleDrag.testAdvanceTime(20);
  idleDrag.testInput.touchmove({ touches: [{ clientX: 600, clientY: 200 }], preventDefault() {} });
  idleDrag.testInput.touchend({ changedTouches: [{ clientX: 600, clientY: 200 }] });
  const fastDuration = Number(idleDrag.testBody.style.transition.match(/transform (\d+)ms/)[1]);
  const pausedDrag = engineHarness(); pausedDrag.layout(config);
  pausedDrag.testInput.touchstart({ touches: [{ clientX: 800, clientY: 200 }] });
  pausedDrag.testAdvanceTime(20);
  pausedDrag.testInput.touchmove({ touches: [{ clientX: 600, clientY: 200 }], preventDefault() {} });
  pausedDrag.testAdvanceTime(150);
  pausedDrag.testInput.touchend({ changedTouches: [{ clientX: 600, clientY: 200 }] });
  const slowDuration = Number(pausedDrag.testBody.style.transition.match(/transform (\d+)ms/)[1]);
  assert(fastDuration < slowDuration, 'same remaining distance settles faster with a fast release than a held finger');
  assert(slowDuration >= 290 && slowDuration <= 320, 'long remaining distance now gets an unhurried release');
  const deferredLayout = engineHarness(); deferredLayout.layout(config); deferredLayout.go(1);
  const beforeDeferred = deferredLayout.testMetrics(); deferredLayout.testResize();
  await new Promise(resolve => setTimeout(resolve, 90));
  assert.deepEqual(deferredLayout.testMetrics(), beforeDeferred, 'late image/font/resize reflow waits until the release transition finishes');
  deferredLayout.testAdvanceTime(400);
  await new Promise(resolve => setTimeout(resolve, 90));
  assert(deferredLayout.testMetrics().rects > beforeDeferred.rects, 'deferred reflow still occurs when motion is finished');
  const gated = engineHarness(); gated.layout(config); gated.present();
  assert(gated.testHidden(), 'raw publisher geometry must stay hidden');
  await Promise.resolve(); await Promise.resolve();
  assert.equal(gated.testFrames.length, 1); gated.testFrames.shift()();
  assert(gated.testHidden(), 'first layout frame is not exposed');
  gated.testFrames.shift()(); await Promise.resolve(); await Promise.resolve();
  assert(!gated.testHidden()); assert.equal(gated.testMessages.at(-1).type, 'ready');
  const imageEvents = {};
  const pendingImage = { complete: false, getBoundingClientRect: () => ({ left: 20, right: 200, top: 20, bottom: 200 }),
    addEventListener: (name, callback) => { imageEvents[name] = callback; }, removeEventListener: name => { delete imageEvents[name]; },
    decode() { throw Error('hidden-page forced decoding must not block presentation'); } };
  const pictureGate = engineHarness(undefined, [pendingImage]); pictureGate.layout(config); pictureGate.present();
  await Promise.resolve(); assert(pictureGate.testHidden()); assert.equal(pictureGate.testFrames.length, 0);
  pendingImage.complete = true; imageEvents.load();
  await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
  assert.equal(pictureGate.testFrames.length, 1); assert(pictureGate.testHidden(), 'loaded dimensions still require final spread layout');
  pictureGate.testFrames.shift()(); pictureGate.testFrames.shift()(); await Promise.resolve();
  assert(!pictureGate.testHidden()); assert.equal(Object.keys(imageEvents).length, 0);
  const shiftingPositions = [0, 1048, 1200];
  const resizing = engineHarness(shiftingPositions);
  resizing.layout(config, { element: 2, fraction: 0.5 });
  assert.equal(JSON.parse(resizing.state()).locator.element, 1, 'intermediate layout has a different first visible element');
  shiftingPositions[1] = 900; shiftingPositions[2] = 1300;
  resizing.testResize(); await new Promise(resolve => setTimeout(resolve, 90));
  assert.equal(JSON.parse(resizing.state()).page, 1, 'resize retains the original semantic anchor instead of the intermediate one');
  const host = new res.EpubResources();
  let active = 0, peak = 0, calls = 0;
  host.archive = { has: name => !name.includes('missing'), readEntry: async name => {
    active++; peak = Math.max(peak, active); calls++;
    await new Promise(resolve => setTimeout(resolve, 2)); active--;
    return new TextEncoder().encode('<html><head><meta name="viewport" content="width=1000,height=700"><style>body{color:red}</style></head><body><img src="art.png"/></body></html>');
  } };
  const replies = ['one.xhtml', 'two.xhtml', 'three.xhtml'].map(p => host.response(res.epubUrl(p)));
  assert(replies.every(r => !r.ready));
  await host.queue;
  assert.equal(peak, 1, 'shared descriptor/inflation is serial');
  for (const reply of replies) {
    assert.equal(reply.code, 200); assert(reply.ready);
    assert.equal(reply.headers.find(h => h.headerKey === 'Cache-Control').headerValue, 'no-store', 'chapter injection is never served stale');
    assert(reply.data.includes('name="readbooks-publisher-viewport"'));
    assert(reply.data.includes('width=device-width,initial-scale=1'));
    assert(reply.data.includes('id="readbooks-first-paint"'), 'raw chapter images cannot paint before spread layout');
    assert(reply.data.includes('<style>body{color:red}</style>'), 'publisher CSS survives');
    assert(reply.headers.find(h => h.headerKey === 'Content-Security-Policy').headerValue.includes("script-src 'none'"));
  }
  const denied = host.response('https://other.invalid/private'); await host.queue;
  assert.equal(denied.code, 404); assert.equal(calls, 3, 'external requests cannot reach the archive');
  const builtins = [];
  host.loadBuiltinFont = async resource => { builtins.push(resource); return new Uint8Array([0, 1, 0, 0]); };
  const songReply = host.response(res.epubUrl('__reader_song__.otf'));
  const kaiReply = host.response(res.epubUrl('__reader_kai__.ttf'));
  await host.queue;
  assert.equal(songReply.code, 200); assert.equal(songReply.mime, 'font/otf');
  assert.equal(songReply.headers.find(h => h.headerKey === 'Cache-Control').headerValue, 'private, max-age=3600');
  assert.equal(kaiReply.code, 200); assert.equal(kaiReply.mime, 'font/ttf');
  assert.deepEqual(builtins, ['fonts/SourceHanSerifSC-Regular.otf', 'fonts/LXGWWenKai-Regular.ttf']);
  assert.equal(calls, 3, 'built-in fonts are read from app resources, not the EPUB archive');
  host.response(res.epubUrl('one.xhtml')); host.response(res.epubUrl('__reader_song__.otf')); await host.queue;
  assert.equal(calls, 3, 'repeat chapter visits reuse verified bytes'); assert.equal(builtins.length, 2, 'large fonts are not repeatedly read');
  host.prefetch('next.xhtml'); await host.queue; assert.equal(calls, 4);
  host.response(res.epubUrl('next.xhtml')); await host.queue; assert.equal(calls, 4, 'prefetched chapter is reused');
  const warnings = []; host.onFailure = message => warnings.push(message);
  host.response(res.epubUrl('missing-fallback.ttf')); await host.queue;
  assert.equal(warnings.length, 0, 'optional CSS font fallback is not an image loading failure');
  host.response(res.epubUrl('missing-image.png')); await host.queue;
  assert.equal(warnings.length, 1); assert(warnings[0].includes('missing-image.png'));
  let completed;
  host.onPrefetchReady = count => { completed = count; };
  const windowOne = Array.from({ length: 50 }, (_, i) => 'chapter-' + i + '.xhtml');
  const priorReads = calls;
  host.deferPrefetch(); host.prefetchWindow(windowOne);
  await new Promise(resolve => setTimeout(resolve, 100));
  assert.equal(calls, priorReads, 'rolling prefetch must not inflate chapters during a touch/settle window');
  assert.equal(host.prefetchPaths.length, 50, 'deferred work stays queued; no lost chapters');
  assert(host.prefetchDeferred);
  host.foregroundRequests = 1; host.prefetchWindow(windowOne);
  await new Promise(resolve => setTimeout(resolve, 80));
  assert.equal(calls, priorReads, 'background prefetch yields to a foreground request');
  host.foregroundRequests = 0;
  for (let n = 0; n < 150 && completed !== 50; n++) await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(completed, 50); assert.equal(calls - priorReads, 50);
  completed = 0; host.prefetchWindow(Array.from({ length: 50 }, (_, i) => 'chapter-' + (i + 1) + '.xhtml'));
  for (let n = 0; n < 150 && completed !== 50; n++) await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(completed, 50); assert.equal(calls - priorReads, 51, 'moving the 50-chapter window loads only one new chapter');
  assert.equal(host.chapterCache.get('chapter-0.xhtml'), undefined, 'old chapters leave the rolling window');
  await host.close(); assert.equal(host.chapterCache.count(), 0); assert.equal(host.cache.count(), 0);
  console.log('EPUB visual core passed: cover colors, URL boundaries, serial resource decoding, CSP, viewport and publisher CSS preservation.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
