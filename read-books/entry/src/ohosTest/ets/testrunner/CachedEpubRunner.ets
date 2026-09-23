import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BookRepo } from '../../../main/ets/data/BookRepo';
import { Db } from '../../../main/ets/data/Db';
import { BookImportService } from '../../../main/ets/reader/BookImportService';

/** One explicitly staged emulator diagnostic file. No personal EPUB is bundled in any HAP. */
export default class CachedEpubRunner implements TestRunner {
  onPrepare(): void {}
  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    if (deviceInfo.productModel.toLowerCase() !== 'emulator') { await delegator.finishTest('Emulator only', 1); return; }
    try {
      const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility' };
      await delegator.addAbilityMonitor(monitor);
      await delegator.startAbility({ bundleName: 'com.healing1.readbooks', abilityName: 'EntryAbility' });
      const ability = await delegator.waitAbilityMonitor(monitor, 10000);
      await delegator.removeAbilityMonitor(monitor);
      await Db.init(ability.context);
      const path: string = ability.context.cacheDir + '/reader-diagnostic.epub';
      if (!fs.accessSync(path)) { throw new Error('Stage the diagnostic EPUB in the emulator application cache first'); }
      const book = await BookImportService.importFromUri(ability.context, path);
      await fs.unlink(path);
      await delegator.finishTest('CACHED_EPUB: imported; libraryCount=' + (await BookRepo.listAll()).length, 0);
    } catch (e) { await delegator.finishTest(e instanceof Error ? e.message : 'Diagnostic import failed', 1); }
  }
}
