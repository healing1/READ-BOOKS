const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.HARMONY_TYPESCRIPT);
const source = fs.readFileSync(path.join(__dirname, '../read-books/entry/src/main/ets/theme/ReaderMotion.ets'), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
let available = true;
let nativeThrows = false;
class Builder {
  pressShadow(value) { this.shadow = value; return this; }
  pointLight(value) { this.point = value; return this; }
  buildEffect() { if (nativeThrows) throw Error('unsupported runtime'); return { shadow: this.shadow, point: this.point }; }
}
const hdsEffect = { HdsEffectBuilder: Builder, PressShadowType: { NONE: 0, BLEND_WHITE: 1 },
  PointLightSourceType: { NONE: 0, SOFT: 1 }, PointLightIlluminatedType: { NONE: 0, BORDER: 1 } };
const exportsObject = {};
new Function('require', 'exports', 'ClickEffectLevel', 'canIUse', 'Color', 'Curve', 'RouteType', compiled)(
  name => name === '@kit.ArkUI' ? { curves: { springMotion: () => 'native-spring' } } :
    name === './ReadingRefresh' ? { ReadingRefresh: { range: () => ({ min: 0, max: 120, expected: 120 }) } } : { hdsEffect },
  exportsObject, { LIGHT: 0 }, () => available, { White: '#FFFFFF' }, { Linear: 'linear', EaseOut: 'ease-out', EaseInOut: 'ease-in-out' }, { Push: 1, Pop: 2 });
const { ReaderMotion, LightFeedback } = exportsObject;
const node = { effect: null, click: null, clickEffect(value) { this.click = value; }, visualEffect(value) { this.effect = value; } };
const feedback = new LightFeedback(false);
feedback.applyNormalAttribute(node);
assert.equal(node.effect.shadow, 0);
assert.equal(node.effect.point.sourceType, 0, 'idle controls must never emit light');
feedback.applyPressedAttribute(node);
assert.equal(node.effect.point.sourceType, 1);
assert.equal(node.effect.shadow, 1);
feedback.applyNormalAttribute(node);
assert.equal(node.effect.point.sourceType, 0, 'release resets the effect');
feedback.applyDisabledAttribute(node);
assert.equal(node.effect.shadow, 0);
new LightFeedback(true).applyPressedAttribute(node);
assert.equal(node.effect.point.sourceType, 0);
assert.equal(node.effect.point.illuminatedType, 0);
new LightFeedback(true).applyNormalAttribute(node);
assert.equal(node.click.scale, 1);
new LightFeedback(false, true).applyPressedAttribute(node);
assert.equal(node.effect.point.sourceType, 0, 'surfaces receive light; they do not emit');
assert.equal(ReaderMotion.spring(true).duration, 0);
assert.equal(ReaderMotion.spring(true).curve, 'linear', 'reduced motion cannot use duration-independent spring curves');
assert.equal(ReaderMotion.change(true).duration, 0);
assert.equal(ReaderMotion.change(false).expectedFrameRateRange.expected, 120);
assert.equal(ReaderMotion.spring(false).expectedFrameRateRange.expected, 120);
assert.equal(ReaderMotion.change(true).expectedFrameRateRange, undefined);
assert.equal(ReaderMotion.pageEnter(false).duration, 340);
assert.equal(ReaderMotion.pageEnter(false).type, 1);
assert.equal(ReaderMotion.pageExit(false).type, 2);
assert.equal(ReaderMotion.pageEnter(true).duration, 0);
assert.equal(ReaderMotion.pageExit(true).duration, 0);
available = false;
node.effect = null;
feedback.applyNormalAttribute(node);
assert.equal(node.effect, null);
available = true;
nativeThrows = true;
assert.doesNotThrow(() => feedback.applyPressedAttribute(node));
console.log('Motion passed: press/release/disabled, reduced motion, non-emitting surfaces, capability fallback.');
