import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BookRepo } from '../../../main/ets/data/BookRepo';
import { Db } from '../../../main/ets/data/Db';
import { BookImportService } from '../../../main/ets/reader/BookImportService';

/** Only imports the explicitly supplied diagnostic sample on the emulator. Never shipped. */
export default class UserEpubRunner implements TestRunner {
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
      if (!(await BookRepo.listAll()).some((book) => book.title === '绍宋')) {
        const resources = delegator.getAppContext().createModuleContext('entry_test').resourceManager;
        const bytes = await resources.getRawFileContent('private/user.epub');
        const path = ability.context.cacheDir + '/user-diagnostic.epub';
        const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try {
          let offset: number = 0;
          while (offset < bytes.length) {
            const count = await fs.write(file.fd, bytes.slice(offset, offset + 128 * 1024).buffer);
            if (count <= 0) { throw new Error('Diagnostic copy failed'); }
            offset += count;
          }
        } finally { await fs.close(file); }
        try { await BookImportService.importFromUri(ability.context, path); }
        finally { await fs.unlink(path); }
      }
      const book = (await BookRepo.listAll()).find((book) => book.title === '绍宋');
      await delegator.finishTest('USER_EPUB:id=' + book?.id + ',source=' + Boolean(book?.sourcePath) + ',characters=' + book?.charCount, 0);
    } catch (e) { await delegator.finishTest(e instanceof Error ? e.message : 'Sample import failed', 1); }
  }
}
