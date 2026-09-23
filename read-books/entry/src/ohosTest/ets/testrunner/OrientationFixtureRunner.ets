import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';

/** Changes only the test application's window, never the system rotation preference. */
export default class OrientationFixtureRunner implements TestRunner {
  onPrepare(): void {}

  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    if (deviceInfo.productModel.toLowerCase() !== 'emulator') {
      await delegator.finishTest('Orientation fixture is emulator-only.', 1);
      return;
    }
    try {
      const mode = abilityDelegatorRegistry.getArguments().parameters['orientation'];
      if (mode !== 'portrait' && mode !== 'landscape' && mode !== 'restore') {
        throw new Error('Expected portrait, landscape, or restore.');
      }
      const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility' };
      await delegator.addAbilityMonitor(monitor);
      await delegator.startAbility({ bundleName: 'com.healing1.readbooks', abilityName: 'EntryAbility' });
      const ability = await delegator.waitAbilityMonitor(monitor, 10000);
      await delegator.removeAbilityMonitor(monitor);
      const mainWindow = await window.getLastWindow(ability.context);
      await mainWindow.setPreferredOrientation(mode === 'portrait' ? window.Orientation.PORTRAIT :
        mode === 'landscape' ? window.Orientation.LANDSCAPE : window.Orientation.AUTO_ROTATION_RESTRICTED);
      await delegator.finishTest('ORIENTATION_OK:' + mode, 0);
    } catch (e) { await delegator.finishTest(e instanceof Error ? e.message : 'Orientation fixture failed', 1); }
  }
}
