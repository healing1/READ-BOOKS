import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { Book } from '../../../main/ets/model/Models';
import { Db } from '../../../main/ets/data/Db';
import { BookRepo } from '../../../main/ets/data/BookRepo';
import { ImportService } from '../../../main/ets/reader/ImportService';
import { CoverStore } from '../../../main/ets/reader/CoverStore';

/** Explicit local QA fixtures, emulator only; never included in the release module. */
export default class CoverFixtureRunner implements TestRunner {
  onPrepare(): void {}

  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    if (deviceInfo.productModel.toLowerCase().indexOf('emulator') < 0) {
      await delegator.finishTest('Cover fixture seeding is emulator-only.', 1);
      return;
    }
    try {
      const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility' };
      await delegator.addAbilityMonitor(monitor);
      await delegator.startAbility({ bundleName: 'com.healing1.readbooks', abilityName: 'EntryAbility' });
      const ability = await delegator.waitAbilityMonitor(monitor, 10000);
      await delegator.removeAbilityMonitor(monitor);
      const context = ability.context;
      await Db.init(context);
      const resources = delegator.getAppContext().createModuleContext('entry_test').resourceManager;
      const bytes = await CoverStore.normalize(await resources.getRawFileContent('formats/cover-fixture.png'));
      for (const title of ['封面验证 TXT', '文字封面 TXT']) {
        let book: Book | undefined = (await BookRepo.listAll()).find((item: Book) => item.title === title);
        if (book === undefined) {
          book = await ImportService.importFromBytes(context, util.TextEncoder.create('utf-8').encodeInto(
            '第一章 阅读\n' + '封面验证仅使用本地测试图书，不访问任何个人文件。'.repeat(100)), title);
        }
        if (title === '封面验证 TXT') {
          await CoverStore.replace(context, book.id, book.coverPath, bytes);
        }
      }
      await delegator.finishTest('Cover fixtures ready: ' + (await BookRepo.listAll())
        .map((book: Book) => book.id + ':' + book.title + ':' + book.coverPath).join('|'), 0);
    } catch (e) { await delegator.finishTest(e instanceof Error ? e.message : 'Cover fixture failed', 1); }
  }
}
