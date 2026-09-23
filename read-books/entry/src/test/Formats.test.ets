import { describe, expect, it, xit } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Book, Chapter } from '../main/ets/model/Models';
import { Db } from '../main/ets/data/Db';
import { BookRepo } from '../main/ets/data/BookRepo';
import { ChapterRepo } from '../main/ets/data/ChapterRepo';
import { ImportService } from '../main/ets/reader/ImportService';
import { BookImportService } from '../main/ets/reader/BookImportService';
import { supportsNativePdf, PDF_UNAVAILABLE } from '../main/ets/reader/PdfCapability';
import { image } from '@kit.ImageKit';
import { EpubSection, EpubSource } from '../main/ets/reader/EpubSource';
import { BookmarkRepo } from '../main/ets/data/BookmarkRepo';
import { EpubArchive } from '../main/ets/reader/EpubArchive';
import { EpubDocument } from '../main/ets/reader/EpubDocument';
import { EpubFonts } from '../main/ets/reader/EpubFonts';

async function fixtureContext(): Promise<common.UIAbilityContext> {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
    .createModuleContext('entry_test') as common.UIAbilityContext;
  await Db.init(context, 'qa_readbooks');
  return context;
}

async function fixtureFile(context: common.UIAbilityContext, name: string): Promise<string> {
  const bytes = await context.resourceManager.getRawFileContent('formats/' + name);
  const path: string = context.cacheDir + '/' + name;
  const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try {
    let offset: number = 0;
    while (offset < bytes.length) {
      const written: number = await fs.write(file.fd, bytes.slice(offset).buffer);
      if (written <= 0) { throw new Error('Fixture write failed'); }
      offset += written;
    }
  } finally {
    await fs.close(file);
  }
  return path;
}

async function cleanup(context: common.UIAbilityContext, path: string, book: Book | null): Promise<void> {
  if (book !== null && book.id > 0) {
    await ImportService.deleteBook(context, book);
    await BookRepo.removeById(book.id);
  }
  if (fs.accessSync(path)) { await fs.unlink(path); }
}

export function formatTests(): void {
  describe('NativeFormats', () => {
    const pdfCase = supportsNativePdf() ? it : xit;
    pdfCase('importsPdfWithFivePagesAndPreservesOriginalOnDeletion', 0, async () => {
      const context = await fixtureContext();
      const path: string = await fixtureFile(context, 'reading-fixture.pdf');
      let book: Book | null = null;
      try {
        book = await BookImportService.importFromUri(context, path);
        expect(book.format).assertEqual('pdf');
        expect(book.charCount).assertEqual(5);
        expect(fs.accessSync(book.filePath)).assertTrue();
        expect(book.coverPath.length > 0).assertTrue();
        const coverSource = image.createImageSource(book.coverPath);
        try {
          const info = await coverSource.getImageInfo();
          expect(info.size.width <= 640 && info.size.height <= 960).assertTrue();
        } finally { await coverSource.release(); }
        expect((await ChapterRepo.listByBook(book.id)).length).assertEqual(0);
        await BookRepo.touchAndSetProgress(book.id, 3);
        expect((await BookRepo.getById(book.id))?.progressCharOffset).assertEqual(3);
        await ImportService.deleteBook(context, book);
        expect(fs.accessSync(path)).assertTrue();
        expect(fs.accessSync(book.filePath)).assertFalse();
        await BookRepo.removeById(book.id);
        book = null;
      } finally { await cleanup(context, path, book); }
    });

    const epubNames: string[] = ['reading-fixture.epub', 'epub2-fixture.epub', 'cover-guide.epub',
      'cover-svg-wrapper.epub', 'cover-filename.epub'];
    epubNames.forEach((name: string) => {
      it('importsSpineUnicodeAndByteIndexes_' + name, 0, async () => {
        const context = await fixtureContext();
        const path: string = await fixtureFile(context, name);
        let book: Book | null = null;
        try {
          book = await BookImportService.importFromUri(context, path);
          expect(book.format).assertEqual('epub');
          expect(book.title).assertEqual('格式验证 EPUB');
          expect(book.author).assertEqual('阅读测试作者');
          const chapters: Chapter[] = await ChapterRepo.listByBook(book.id);
          expect(chapters.length).assertEqual(3);
          expect(chapters.map((chapter: Chapter) => chapter.title).join('|'))
            .assertEqual('山间来信|海边的下午|最后一页');
          let restored: string = '';
          for (let index: number = 0; index < chapters.length; index++) {
            expect(chapters[index].byteStart >= 0).assertTrue();
            restored += await ImportService.readChapter(book, chapters[index]);
          }
          expect(restored.length).assertEqual(book.charCount);
          expect(restored.includes('实体 & < > 和 emoji 😀')).assertTrue();
          expect(restored.includes('body{')).assertFalse();
          expect(restored.indexOf('第一章') < restored.indexOf('第二章')).assertTrue();
          expect(book.coverPath.length > 0).assertTrue();
          expect(fs.accessSync(book.coverPath)).assertTrue();
          const coverSource = image.createImageSource(book.coverPath);
          try {
            const info = await coverSource.getImageInfo();
            expect(info.size.width).assertEqual(320);
            expect(info.size.height).assertEqual(460);
          } finally { await coverSource.release(); }
          await ImportService.recover(context);
          expect(fs.accessSync(book.filePath)).assertTrue();
          expect(fs.accessSync(book.coverPath)).assertTrue();
          const cover: string = book.coverPath;
          const original: string = book.sourcePath;
          expect(fs.accessSync(original)).assertTrue();
          await ImportService.deleteBook(context, book);
          expect(fs.accessSync(path)).assertTrue();
          expect(fs.accessSync(cover)).assertFalse();
          expect(fs.accessSync(original)).assertFalse();
          await BookRepo.removeById(book.id);
          book = null;
        } finally { await cleanup(context, path, book); }
      });
    });

    ['qa-illustrated.epub', 'qa-fixed.epub', 'qa-obfuscated.epub'].forEach((name: string) => {
      it('preservesOriginalImagesStylesFontsAndLocators_' + name, 0, async () => {
        const context = await fixtureContext();
        const path = await fixtureFile(context, name);
        let book: Book | null = null;
        try {
          book = await BookImportService.importFromUri(context, path);
          const sections = JSON.parse(book.epubIndex) as EpubSection[];
          expect(sections.length).assertEqual(3);
          expect(sections[0].fixed).assertEqual(name === 'qa-fixed.epub');
          expect(sections[2].end > sections[2].start).assertTrue();
          const file = await fs.open(book.sourcePath, fs.OpenMode.READ_ONLY);
          try {
            const stat = await fs.stat(file.fd);
            const archive = new EpubArchive(file.fd, stat.size, stat.mtime);
            await archive.initialize();
            expect(archive.has('OPS/art.png')).assertTrue();
            expect((await archive.readEntry('OPS/art.png', 1024 * 1024))[0]).assertEqual(0x89);
            expect((await archive.readText('OPS/style.css')).includes('@font-face')).assertTrue();
            expect((await archive.readEntry('OPS/book.ttf', 1024 * 1024)).length > 10000).assertTrue();
            if (name === 'qa-obfuscated.epub') {
              const metadata = EpubDocument.package(await archive.readText('OPS/package.opf'), 'OPS/package.opf');
              const fonts = await EpubFonts.inspect(archive, metadata);
              const decoded = fonts.decode('OPS/book.ttf', await archive.readEntry('OPS/book.ttf', 1024 * 1024));
              const original = await context.resourceManager.getRawFileContent('formats/Reading-QA.ttf');
              expect(decoded.length).assertEqual(original.length);
              expect(decoded.every((byte: number, index: number) => byte === original[index])).assertTrue();
            }
            const toc = EpubDocument.navigationEntries(await archive.readText('OPS/nav.xhtml'), 'OPS/nav.xhtml');
            expect(toc.length).assertEqual(4);
            expect(toc[2].fragment).assertEqual('detail');
            expect(toc[2].depth > toc[1].depth).assertTrue();
          } finally { await fs.close(file); }
          const location = JSON.stringify({ path: sections[1].path, element: 8, fraction: 0.5 });
          await BookRepo.touchAndSetProgress(book.id, sections[1].start, location);
          expect((await BookRepo.getById(book.id))?.epubLocation).assertEqual(location);
          await ImportService.recover(context);
          expect(fs.accessSync(book.sourcePath)).assertTrue();
          if (name === 'qa-illustrated.epub') {
            const chapters = await ChapterRepo.listByBook(book.id);
            expect(await ImportService.readChapter(book, chapters[chapters.length - 1])).assertEqual('\uFFFC\n\n');
          }
        } finally { await cleanup(context, path, book); }
      });
    });

    it('reattachesOriginalEditionWithoutChangingLegacyProgressOrBookmarks', 0, async () => {
      const context = await fixtureContext();
      const path = await fixtureFile(context, 'reading-fixture.epub');
      const wrong = await fixtureFile(context, 'qa-illustrated.epub');
      let book: Book | null = null;
      try {
        book = await BookImportService.importFromUri(context, path);
        await BookRepo.touchAndSetProgress(book.id, 42);
        const bookmark = await BookmarkRepo.add(book.id, 42, '旧版书签');
        const store = await Db.get();
        store.executeSync("UPDATE books SET source_path = '', epub_index = '' WHERE id = ?", [book.id]);
        book.sourcePath = ''; book.epubIndex = '';
        let mismatch: boolean = false;
        try { await EpubSource.attach(context, book, wrong); } catch (_) { mismatch = true; }
        expect(mismatch).assertTrue();
        expect((await BookRepo.getById(book.id))?.sourcePath).assertEqual('');
        await EpubSource.attach(context, book, path);
        const upgraded = await BookRepo.getById(book.id);
        expect(upgraded?.progressCharOffset).assertEqual(42);
        expect((await BookmarkRepo.listByBook(book.id))[0].id).assertEqual(bookmark);
        expect(upgraded !== null && fs.accessSync(upgraded.sourcePath)).assertTrue();
        book = upgraded;
        await ImportService.recover(context);
      } finally { await cleanup(context, path, book); await fs.unlink(wrong); }
    });

    const rejectedNames: string[] = ['invalid-fixture.pdf', 'encrypted-fixture.pdf',
      'invalid-fixture.epub', 'unsafe-fixture.epub', 'encrypted-fixture.epub'];
    rejectedNames.forEach((name: string) => {
      const formatCase = name.endsWith('.pdf') ? pdfCase : it;
      formatCase('rejectsWithoutPublishingOrDeletingOriginal_' + name, 0, async () => {
        const context = await fixtureContext();
        const path: string = await fixtureFile(context, name);
        const before = (await BookRepo.listAll()).map((book: Book) => book.id).join(',');
        let imported: Book | null = null;
        let rejected: boolean = false;
        try {
          try { imported = await BookImportService.importFromUri(context, path); }
          catch (e) { rejected = true; }
          expect(rejected).assertTrue();
          expect((await BookRepo.listAll()).map((book: Book) => book.id).join(',')).assertEqual(before);
          expect(fs.accessSync(path)).assertTrue();
        } finally { await cleanup(context, path, imported); }
      });
    });

    if (!supportsNativePdf()) {
      it('reportsUnavailablePdfKitWithoutPublishingACopy', 0, async () => {
        const context = await fixtureContext();
        const path: string = await fixtureFile(context, 'reading-fixture.pdf');
        let imported: Book | null = null;
        let message: string = '';
        try {
          try { imported = await BookImportService.importFromUri(context, path); }
          catch (e) { message = e instanceof Error ? e.message : ''; }
          expect(message).assertEqual(PDF_UNAVAILABLE);
          expect(imported).assertNull();
          expect(fs.accessSync(path)).assertTrue();
        } finally { await cleanup(context, path, imported); }
      });
    }
  });
}
