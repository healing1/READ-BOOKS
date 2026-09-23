const fs = require('node:fs');
const path = require('node:path');
const cli = process.env.HARMONYOS_CLI_HOME;
if (!cli) throw new Error('Set HARMONYOS_CLI_HOME first.');
const json5 = require(path.join(cli, 'hvigor/hvigor-ohos-plugin/node_modules/json5'));
const root = path.join(__dirname, '../read-books');
const profilePath = path.join(root, 'build-profile.json5');
const localPath = path.join(root, 'signing.local.json');
const profile = json5.parse(fs.readFileSync(profilePath, 'utf8'));
if (profile.app.signingConfigs?.length) {
  if (fs.existsSync(localPath)) {
    if (!process.argv.includes('--replace')) throw new Error('Local signing file already exists; use --replace to preserve a backup and update it.');
    fs.copyFileSync(localPath, path.join(root, `signing.local.${Date.now()}.json`), fs.constants.COPYFILE_EXCL);
  }
  fs.writeFileSync(localPath, JSON.stringify(profile.app.signingConfigs, null, 2) + '\n');
  profile.app.signingConfigs = [];
  for (const product of profile.app.products) delete product.signingConfig;
  fs.writeFileSync(profilePath, JSON.stringify(profile, null, 2) + '\n');
  console.log('Moved machine signing configuration to ignored signing.local.json.');
}
