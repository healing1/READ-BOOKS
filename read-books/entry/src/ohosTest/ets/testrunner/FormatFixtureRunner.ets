import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Db } from '../../../main/ets/data/Db';
import { BookRepo } from '../../../main/ets/data/BookRepo';
import { BookImportService } from '../../../main/ets/reader/BookImportService';
import { supportsNativePdf } from '../../../main/ets/reader/PdfCapability';
import { deviceInfo } from '@kit.BasicServicesKit';

/** Explicit QA-only seeding. Not packaged in the production entry module. */
export default class FormatFixtureRunner implements TestRunner {
  onPrepare(): void {}

  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    if (deviceInfo.productModel.toLowerCase().indexOf('emulator') < 0) {
      await delegator.finishTest('Format fixture seeding is emulator-only.', 1);
      return;
    }
    try {
      const app = delegator.getAppContext();
      const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility' };
      await delegator.addAbilityMonitor(monitor);
      await delegator.startAbility({ bundleName: 'com.healing1.readbooks', abilityName: 'EntryAbility' });
      const ability = await delegator.waitAbilityMonitor(monitor, 10000);
      const context = ability.context;
      await delegator.removeAbilityMonitor(monitor);
      const resources = app.createModuleContext('entry_test').resourceManager;
      await Db.init(context);
      const names: string[] = supportsNativePdf() ? ['reading-fixture.epub', 'reading-fixture.pdf'] : ['reading-fixture.epub'];
      for (const name of names) {
        const existing = await BookRepo.listAll();
        if (existing.some((book) => book.title === (name.endsWith('.epub') ? '格式验证 EPUB' : 'reading-fixture'))) { continue; }
        const bytes = await resources.getRawFileContent('formats/' + name);
        const path: string = context.cacheDir + '/' + name;
        const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        try {
          let offset: number = 0;
          while (offset < bytes.length) {
            const count: number = await fs.write(file.fd, bytes.slice(offset).buffer);
            if (count <= 0) { throw new Error('QA fixture write failed'); }
            offset += count;
          }
        } finally { await fs.close(file); }
        try { await BookImportService.importFromUri(context, path); }
        finally { if (fs.accessSync(path)) { await fs.unlink(path); } }
      }
      const imported = await BookRepo.listAll();
      await delegator.finishTest('QA fixtures imported; filesDir=' + context.filesDir + '; databaseDir=' + context.databaseDir +
        '; books=' + imported.map((book) => book.id + ':' + book.title + ':' + book.filePath + ':' + fs.accessSync(book.filePath)).join('|') +
        '; native PDF available=' + supportsNativePdf(), 0);
    } catch (e) {
      await delegator.finishTest(e instanceof Error ? e.message : 'Fixture setup failed', 1);
    }
  }
}
