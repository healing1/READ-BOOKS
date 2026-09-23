// Keep private build materials in the user's chosen HarmonyOS tool directory.
const fs = require('node:fs');
const path = require('node:path');
const local = path.join(__dirname, '../read-books/signing.local.json');
const root = path.join(process.env.USERPROFILE, 'DevTools/HarmonyOS/signing/read-books');
const configs = JSON.parse(fs.readFileSync(local, 'utf8'));
fs.mkdirSync(root, { recursive: true });
for (const config of configs) {
  const material = path.join(path.dirname(config.material.storeFile), 'material');
  const destination = path.join(root, 'material');
  if (fs.existsSync(material) && path.resolve(material) !== path.resolve(destination)) {
    fs.cpSync(material, destination, { recursive: true });
  }
  for (const key of ['storeFile', 'profile', 'certpath']) {
    const source = config.material[key];
    if (!source || !fs.statSync(source).isFile()) throw new Error('Missing signing material: ' + key);
    const target = path.join(root, path.basename(source));
    if (path.resolve(source) !== path.resolve(target)) fs.copyFileSync(source, target);
    config.material[key] = target;
  }
}
fs.writeFileSync(local, JSON.stringify(configs, null, 2) + '\n');
console.log('Build signing materials copied to ' + root + '; original CLI-managed cache retained.');
