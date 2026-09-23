const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.HARMONY_TYPESCRIPT);
const source = fs.readFileSync(path.join(__dirname, '../read-books/entry/src/main/ets/theme/NativeMaterial.ets'), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
let supportedTypes = [101];
let available = true;
let failQuery = false;
const deviceInfo = { sdkApiVersion: 24 };
const hdsMaterial = { MaterialType: { NONE: 0, ADAPTIVE: 100, IMMERSIVE: 101 },
  MaterialLevel: { ADAPTIVE: 10 }, getSystemMaterialTypes() { if (failQuery) throw Error('unsupported'); return supportedTypes; } };
const exportsObject = {};
new Function('require', 'exports', 'canIUse', compiled)(
  name => name === '@kit.BasicServicesKit' ? { deviceInfo } : { hdsMaterial }, exportsObject, () => available);
const { NativeMaterial } = exportsObject;
assert(NativeMaterial.supported());
assert.equal(NativeMaterial.options(false).materialType, 101);
assert.equal(NativeMaterial.options(true).materialType, 0, 'reduced motion disables immersive material, not just its quality');
supportedTypes = [100];
assert.equal(NativeMaterial.options(false).materialType, 100, 'unsupported immersion follows OS policy');
failQuery = true;
assert.equal(NativeMaterial.options(false).materialType, 100);
deviceInfo.sdkApiVersion = 22;
assert(!NativeMaterial.supported(), 'API20 point light does not imply API23 immersive material');
deviceInfo.sdkApiVersion = 24;
available = false;
assert(!NativeMaterial.supported());
console.log('Native material passed: API/capability guards, supported-type query, fallback and reduced-motion opt-out.');
