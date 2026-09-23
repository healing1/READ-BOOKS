import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BookRepo } from '../../../main/ets/data/BookRepo';
import { Db } from '../../../main/ets/data/Db';
import { BookImportService } from '../../../main/ets/reader/BookImportService';

/** Emulator-only locally authored UI fixtures. Does not touch existing books or reader settings. */
export default class EpubFixtureRunner implements TestRunner {
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
      const context = ability.context;
      await Db.init(context);
      const resources = delegator.getAppContext().createModuleContext('entry_test').resourceManager;
      for (const name of ['qa-illustrated.epub', 'qa-fixed.epub']) {
        const title = name === 'qa-fixed.epub' ? '原版绘本 · QA' : '山海图文 · QA';
        if ((await BookRepo.listAll()).some((book) => book.title === title)) { continue; }
        const path = context.cacheDir + '/' + name;
        const bytes = await resources.getRawFileContent('formats/' + name);
        const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try {
          let offset: number = 0;
          while (offset < bytes.length) {
            const count = await fs.write(file.fd, bytes.slice(offset).buffer);
            if (count <= 0) { throw new Error('Fixture write failed'); }
            offset += count;
          }
        } finally { await fs.close(file); }
        try { await BookImportService.importFromUri(context, path); }
        finally { await fs.unlink(path); }
      }
      await delegator.finishTest('EPUB_FIXTURES: ' + (await BookRepo.listAll()).map((book) => book.id + ':' + book.title).join('|'), 0);
    } catch (e) { await delegator.finishTest(e instanceof Error ? e.message : 'Fixture failed', 1); }
  }
}
