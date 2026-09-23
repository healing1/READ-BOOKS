import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { hvigor } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

hvigor.getRootNode().afterNodeEvaluate(() => {
  const signingFile = path.join(__dirname, 'signing.local.json');
  if (fs.existsSync(signingFile)) {
    const context = hvigor.getRootNode().getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    const profile = context.getBuildProfileOpt();
    const signing = JSON.parse(fs.readFileSync(signingFile, 'utf8'));
    profile.app.signingConfigs = signing;
    profile.app.products.forEach((product) => { product.signingConfig = signing[0].name; });
    context.setBuildProfileOpt(profile);
  }
});

export default {
  system: appTasks,
  plugins: []
}
