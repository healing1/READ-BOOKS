import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Book } from '../main/ets/model/Models';
import { Db } from '../main/ets/data/Db';
import { BookRepo } from '../main/ets/data/BookRepo';
import { CoverStore } from '../main/ets/reader/CoverStore';
import { CoverService } from '../main/ets/reader/CoverService';
import { EpubDocument } from '../main/ets/reader/EpubDocument';
import { ImportService } from '../main/ets/reader/ImportService';
import { ImportActivity } from '../main/ets/reader/ImportActivity';

async function coverContext(): Promise<common.UIAbilityContext> {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
    .createModuleContext('entry_test') as common.UIAbilityContext;
  await Db.init(context, 'qa_readbooks');
  return context;
}

async function cleanup(context: common.UIAbilityContext, book: Book): Promise<void> {
  const current: Book | null = await BookRepo.getById(book.id);
  if (current !== null) { await ImportService.deleteBook(context, current); }
  await BookRepo.removeById(book.id);
  await ImportService.recover(context);
}

export function coverTests(): void {
  describe('NativeCovers', () => {
    it('resolvesXhtmlAndSvgWrapperImagesWithoutFetchingRemotePaths', 0, () => {
      const paths: string[] = EpubDocument.coverImages('<html><body><img src="https://example.com/cover.png"/>' +
        '<img src="../../../outside.png"/><svg><image xlink:href="../images/front%20cover.jpg"/></svg>' +
        '<img src="../images/front%20cover.jpg"/><script><img src="evil.png"/></script></body></html>', 'OPS/text/cover.xhtml');
      expect(paths.join('|')).assertEqual('OPS/images/front cover.jpg');
    });

    it('replacesTxtCoverAtomicallyWithoutChangingBookContentOrProgress', 0, async () => {
      const context = await coverContext();
      const book = await ImportService.importFromBytes(context, util.TextEncoder.create('utf-8').encodeInto('第一章\n封面替换测试正文'), '封面测试');
      try {
        await BookRepo.touchAndSetProgress(book.id, 5);
        const bytes: Uint8Array = await context.resourceManager.getRawFileContent('formats/cover-fixture.png');
        await CoverStore.replace(context, book.id, '', await CoverStore.normalize(bytes));
        const current = await BookRepo.getById(book.id) as Book;
        expect(current.coverPath.endsWith('_cover.png')).assertTrue();
        expect(current.filePath).assertEqual(book.filePath);
        expect(current.charCount).assertEqual(book.charCount);
        expect(current.progressCharOffset).assertEqual(5);
        expect(fs.accessSync(current.coverPath)).assertTrue();
        expect(ImportActivity.has(current.coverPath)).assertFalse();
        await ImportService.recover(context);
        expect(fs.accessSync(current.coverPath)).assertTrue();
        await CoverStore.replace(context, current.id, current.coverPath, await CoverStore.normalize(bytes));
        const replaced = await BookRepo.getById(book.id) as Book;
        expect(replaced.coverPath !== current.coverPath).assertTrue();
        expect(fs.accessSync(current.coverPath)).assertFalse();
        await CoverService.useText(context, replaced);
        expect((await BookRepo.getById(book.id))?.coverPath).assertEqual('');
        expect(fs.accessSync(replaced.coverPath)).assertFalse();
      } finally { await cleanup(context, book); }
    });

    it('doesNotOverwriteNewerCoverWithStaleBackgroundRepair', 0, async () => {
      const context = await coverContext();
      const book = await ImportService.importFromBytes(context, util.TextEncoder.create('utf-8').encodeInto('正文'), '封面冲突测试');
      try {
        const beforeCount: number = (await fs.listFile(Db.booksDirectory(context)))
          .filter((path: string) => path.endsWith('_cover.png')).length;
        const bytes = await CoverStore.normalize(await context.resourceManager.getRawFileContent('formats/cover-fixture.png'));
        await CoverStore.replace(context, book.id, '', bytes);
        const current = await BookRepo.getById(book.id) as Book;
        let failed: boolean = false;
        try { await CoverStore.replace(context, book.id, '', bytes); } catch (e) { failed = true; }
        expect(failed).assertTrue();
        expect((await BookRepo.getById(book.id))?.coverPath).assertEqual(current.coverPath);
        const files = await fs.listFile(Db.booksDirectory(context));
        expect(files.filter((path: string) => path.endsWith('_cover.png')).length).assertEqual(beforeCount + 1);
      } finally { await cleanup(context, book); }
    });

    it('doesNotResurrectDeletedBookOrLeaveAnOrphanThumbnail', 0, async () => {
      const context = await coverContext();
      const book = await ImportService.importFromBytes(context, util.TextEncoder.create('utf-8').encodeInto('正文'), '删除冲突测试');
      try {
        await ImportService.deleteBook(context, book);
        const before = (await fs.listFile(Db.booksDirectory(context))).sort().join('|');
        let failed: boolean = false;
        try { await CoverStore.replace(context, book.id, '', await CoverStore.normalize(
          await context.resourceManager.getRawFileContent('formats/cover-fixture.png'))); } catch (e) { failed = true; }
        expect(failed).assertTrue();
        expect(await BookRepo.getById(book.id)).assertNull();
        expect((await fs.listFile(Db.booksDirectory(context))).sort().join('|')).assertEqual(before);
      } finally { await cleanup(context, book); }
    });

    it('rejectsUndecodableImageAndProtectsExternalFilesFromCleanup', 0, async () => {
      const context = await coverContext();
      let failed: boolean = false;
      try { await CoverStore.normalize(new Uint8Array([0x89, 0x50, 0x4E, 0x47])); } catch (e) { failed = true; }
      expect(failed).assertTrue();
      const path: string = context.cacheDir + '/book_1_1_cover.png';
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.closeSync(file);
      try {
        await CoverStore.removeUnused(context, path);
        expect(fs.accessSync(path)).assertTrue();
      } finally { fs.unlinkSync(path); }
    });
  });
}
