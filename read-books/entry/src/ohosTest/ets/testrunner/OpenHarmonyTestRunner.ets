import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import readerCoreTests from '../../../test/List.test';

export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {}

  onRun(): void {
    Hypium.hypiumTest(abilityDelegatorRegistry.getAbilityDelegator(),
      abilityDelegatorRegistry.getArguments(), () => { readerCoreTests(true); });
  }
}
