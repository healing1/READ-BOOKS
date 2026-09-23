import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { util } from '@kit.ArkTS';
import { Db } from '../main/ets/data/Db';
import { BookRepo } from '../main/ets/data/BookRepo';
import { BookmarkRepo } from '../main/ets/data/BookmarkRepo';
import { ReadingActivityRepo } from '../main/ets/data/ReadingActivityRepo';
import { ImportService } from '../main/ets/reader/ImportService';

export function activityTests(): void {
  describe('ReadingActivity', () => {
    it('splitsReadingTimeAtLocalMidnightAndSerializesUpdates', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
        .createModuleContext('entry_test') as common.UIAbilityContext;
      const store = await Db.init(context, 'qa_readbooks');
      const keys: string[] = ['2098-01-01', '2098-01-02'];
      const existing = store.querySqlSync('SELECT day FROM reading_days WHERE day IN (?, ?)', keys);
      try {
        expect(existing.rowCount).assertEqual(0);
      } finally {
        existing.close();
      }
      try {
        const start: number = new Date(2098, 0, 1, 23, 59, 58).getTime();
        await ReadingActivityRepo.recordInterval(start, start + 6000);
        await Promise.all([ReadingActivityRepo.recordInterval(start, start + 1000),
          ReadingActivityRepo.recordInterval(start, start + 1000)]);
        const rows = store.querySqlSync('SELECT day, seconds FROM reading_days WHERE day IN (?, ?) ORDER BY day', keys);
        try {
          expect(rows.goToFirstRow()).assertTrue();
          expect(rows.getLong(1)).assertEqual(4);
          expect(rows.goToNextRow()).assertTrue();
          expect(rows.getLong(1)).assertEqual(4);
        } finally {
          rows.close();
        }
      } finally {
        store.executeSync('DELETE FROM reading_days WHERE day IN (?, ?)', keys);
      }
    });

    it('preservesLatestProgressAndDeduplicatesBookmarks', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
        .createModuleContext('entry_test') as common.UIAbilityContext;
      await Db.init(context, 'qa_readbooks');
      const book = await ImportService.importFromBytes(context,
        util.TextEncoder.create('utf-8').encodeInto('阅读记录测试正文'.repeat(100)), 'Activity Fixture');
      try {
        await Promise.all([BookRepo.touchAndSetProgress(book.id, 10), BookRepo.touchAndSetProgress(book.id, 200),
          BookRepo.touchAndSetProgress(book.id, 50)]);
        expect((await BookRepo.getById(book.id))?.progressCharOffset).assertEqual(50);
        await Promise.all([BookmarkRepo.add(book.id, 50, '第一条'), BookmarkRepo.add(book.id, 50, '重复点击')]);
        const bookmarks = await BookmarkRepo.listByBook(book.id);
        expect(bookmarks.length).assertEqual(1);
        expect(bookmarks[0].charOffset).assertEqual(50);
        await ReadingActivityRepo.setFinished(book.id, true);
        await ReadingActivityRepo.setFinished(book.id, true);
        expect((await ReadingActivityRepo.summary(30)).finishedIds.filter((id: number) => id === book.id).length)
          .assertEqual(1);
        await ImportService.deleteBook(context, book);
        expect((await ReadingActivityRepo.summary(30)).finishedIds.indexOf(book.id)).assertEqual(-1);
        expect((await BookmarkRepo.listByBook(book.id)).length).assertEqual(0);
      } finally {
        await BookRepo.removeById(book.id);
        await ImportService.recover(context);
      }
    });
  });
}
