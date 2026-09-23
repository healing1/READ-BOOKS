import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Book, Chapter } from '../main/ets/model/Models';
import { Db } from '../main/ets/data/Db';
import { BookRepo } from '../main/ets/data/BookRepo';
import { ChapterRepo } from '../main/ets/data/ChapterRepo';
import { ChapterDetector, StreamingChapterDetector, utf8ByteLength } from '../main/ets/reader/ChapterDetector';
import { StreamingTextNormalizer, StreamingTextValidator, StreamingUtf8Validator } from '../main/ets/reader/EncodingDetector';
import { ImportService, MAX_SOURCE_BYTES } from '../main/ets/reader/ImportService';

async function storageContext(): Promise<common.UIAbilityContext> {
  const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const context = appContext.createModuleContext('entry_test') as common.UIAbilityContext;
  await Db.init(context, 'qa_readbooks');
  return context;
}

async function removeFixture(context: common.UIAbilityContext, book: Book | null): Promise<void> {
  if (book !== null && book.id > 0) {
    if (fs.accessSync(book.filePath)) {
      await fs.unlink(book.filePath);
    }
    await BookRepo.removeById(book.id);
  }
}

export function storageTests(): void {
  describe('StreamingStorage', () => {
    it('normalizesBomAndCrLfAcrossEmptyDecoderChunks', 0, () => {
      const normalizer: StreamingTextNormalizer = new StreamingTextNormalizer();
      let text: string = normalizer.push('');
      text += normalizer.push('\uFEFF标题\r');
      text += normalizer.push('');
      text += normalizer.push('\n正文\r后续\r');
      text += normalizer.push('', true);
      expect(text).assertEqual('标题\n正文\n后续\n');
    });

    it('validatesUtf8AcrossEveryMultibyteBoundary', 0, () => {
      const valid: StreamingUtf8Validator = new StreamingUtf8Validator();
      const bytes: Uint8Array = util.TextEncoder.create('utf-8').encodeInto('A中😀\uFEFF');
      for (let i: number = 0; i < bytes.length; i++) {
        valid.push(bytes.subarray(i, i + 1));
      }
      expect(valid.finish()).assertTrue();
      const samples: Uint8Array[] = [new Uint8Array([0xE0, 0x80, 0x80]),
        new Uint8Array([0xED, 0xA0, 0x80]), new Uint8Array([0xF4, 0x90, 0x80, 0x80]),
        new Uint8Array([0xF0, 0x9F, 0x98])];
      samples.forEach((sample: Uint8Array) => {
        const invalid: StreamingUtf8Validator = new StreamingUtf8Validator();
        for (let i: number = 0; i < sample.length; i++) {
          invalid.push(sample.subarray(i, i + 1));
        }
        expect(invalid.finish()).assertFalse();
      });
    });

    it('appliesContentValidationToTheWholeStream', 0, () => {
      const valid: StreamingTextValidator = new StreamingTextValidator();
      valid.push('\u0001\u0002\u0003');
      valid.push('正文'.repeat(2000));
      valid.finish();
      const invalid: StreamingTextValidator = new StreamingTextValidator();
      invalid.push('标题\u0001');
      invalid.push('正文\u0002\u0003');
      let rejected: boolean = false;
      try {
        invalid.finish();
      } catch (e) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('preservesHeadingsAndByteOffsetsWithSplitSurrogatePairs', 0, () => {
      const text: string = '前言😀\n第一章 开始\n' + '字'.repeat(49990) + '😀正文\nchapter 2 Continue\n结尾';
      const expected: Chapter[] = ChapterDetector.detect(text, 8);
      const sizes: number[] = [1, 7, 16381];
      sizes.forEach((size: number) => {
        const detector: StreamingChapterDetector = new StreamingChapterDetector(8);
        for (let offset: number = 0; offset < text.length; offset += size) {
          detector.push(text.substring(offset, offset + size));
        }
        const chapters: Chapter[] = detector.finish();
        expect(chapters.length).assertEqual(expected.length);
        for (let i: number = 0; i < chapters.length; i++) {
          expect(chapters[i].title).assertEqual(expected[i].title);
          expect(chapters[i].startOffset).assertEqual(expected[i].startOffset);
          expect(chapters[i].endOffset).assertEqual(expected[i].endOffset);
          expect(chapters[i].byteStart).assertEqual(utf8ByteLength(text.substring(0, chapters[i].startOffset)));
          expect(chapters[i].byteEnd).assertEqual(utf8ByteLength(text.substring(0, chapters[i].endOffset)));
        }
      });
    });

    it('boundsUnbrokenParagraphsWithoutSplittingUnicode', 0, () => {
      const detector: StreamingChapterDetector = new StreamingChapterDetector();
      detector.push('字'.repeat(49999) + '\uD83D');
      detector.push('\uDE00' + '后'.repeat(50001));
      const chapters: Chapter[] = detector.finish();
      expect(chapters.length).assertEqual(3);
      expect(chapters[0].endOffset).assertEqual(50001);
      expect(chapters[0].byteEnd).assertEqual(49999 * 3 + 4);
      expect(chapters[1].startOffset).assertEqual(chapters[0].endOffset);
      expect(chapters[2].endOffset).assertEqual(100002);
      expect(chapters[0].title).assertEqual('片段 1');
    });

    it('importsReadsAndMigratesMultibyteChapterIndexes', 0, async () => {
      const context = await storageContext();
      const original: string = '\uFEFF第一章 开始\r\n' + '字'.repeat(49995) + '😀\r\n第二章 后续\n\uFEFF正文';
      const expected: string = original.substring(1).replace(/\r\n?/g, '\n');
      let book: Book | null = null;
      try {
        book = await ImportService.importFromBytes(context, util.TextEncoder.create('utf-8').encodeInto(original), 'Storage Unicode');
        const chapters: Chapter[] = await ChapterRepo.listByBook(book.id);
        expect(book.charCount).assertEqual(expected.length);
        let restored: string = '';
        for (let i: number = 0; i < chapters.length; i++) {
          restored += await ImportService.readChapter(book, chapters[i]);
        }
        expect(restored).assertEqual(expected);
        const crossing: number = chapters[0].endOffset - 3;
        expect(await ImportService.readExcerpt(book, crossing, 12)).assertEqual(expected.substring(crossing, crossing + 12));
        await BookRepo.touchAndSetProgress(book.id, 12345);
        const store = await Db.get();
        store.executeSync('UPDATE chapters SET byte_start = -1, byte_end = -1 WHERE book_id = ?', [book.id]);
        const migrated: Chapter[] = await ImportService.ensureChapterIndex(book, await ChapterRepo.listByBook(book.id));
        expect(migrated.length).assertEqual(chapters.length);
        for (let i: number = 0; i < chapters.length; i++) {
          expect(migrated[i].byteStart).assertEqual(chapters[i].byteStart);
          expect(migrated[i].byteEnd).assertEqual(chapters[i].byteEnd);
        }
        expect((await BookRepo.getById(book.id))?.progressCharOffset).assertEqual(12345);
      } finally {
        await removeFixture(context, book);
      }
    });

    it('importsUtf16AndGb18030WithoutCorruptingNewlines', 0, async () => {
      const context = await storageContext();
      const samples: Uint8Array[] = [new Uint8Array([0xFE, 0xFF, 0, 0x41, 0, 0x0D, 0, 0x0A, 0x4E, 0x2D, 0x65, 0x87]),
        new Uint8Array([0xC4, 0xE3, 0xBA, 0xC3, 0x0D, 0x0A, 0xD5, 0xFD, 0xCE, 0xC4])];
      const expected: string[] = ['A\n中文', '你好\n正文'];
      for (let i: number = 0; i < samples.length; i++) {
        let book: Book | null = null;
        try {
          book = await ImportService.importFromBytes(context, samples[i], 'Storage Encoding');
          const chapters: Chapter[] = await ChapterRepo.listByBook(book.id);
          expect(await ImportService.readChapter(book, chapters[0])).assertEqual(expected[i]);
        } finally {
          await removeFixture(context, book);
        }
      }
    });

    it('rollsBackBookAndChaptersWhenAChapterInsertFails', 0, async () => {
      await storageContext();
      const book: Book = new Book();
      book.title = 'Storage rollback ' + Date.now();
      book.charCount = 2;
      const first: Chapter = new Chapter();
      first.endOffset = 1;
      const duplicate: Chapter = new Chapter();
      duplicate.startOffset = 1;
      duplicate.endOffset = 2;
      let rejected: boolean = false;
      try {
        book.id = await BookRepo.insertWithChapters(book, [first, duplicate]);
      } catch (e) {
        rejected = true;
      }
      try {
        expect(rejected).assertTrue();
        const books: Book[] = await BookRepo.listAll();
        expect(books.some((candidate: Book) => candidate.title === book.title)).assertFalse();
      } finally {
        if (book.id > 0) {
          await BookRepo.removeById(book.id);
        }
      }
    });

    it('rejectsTruncatedChapterFilesAndUnsafeDeletionPaths', 0, async () => {
      const context = await storageContext();
      let book: Book | null = null;
      try {
        book = await ImportService.importFromBytes(context, util.TextEncoder.create('utf-8').encodeInto('第一章\n正文😀'), 'Storage Truncate');
        const chapters: Chapter[] = await ChapterRepo.listByBook(book.id);
        await fs.truncate(book.filePath, 2);
        let truncated: boolean = false;
        try {
          await ImportService.readChapter(book, chapters[0]);
        } catch (e) {
          truncated = true;
        }
        expect(truncated).assertTrue();
        const invalid: Book = new Book();
        invalid.id = book.id;
        invalid.filePath = Db.booksDirectory(context) + '/../outside.txt';
        let unsafe: boolean = false;
        try {
          await ImportService.deleteBook(context, invalid);
        } catch (e) {
          unsafe = true;
        }
        expect(unsafe).assertTrue();
        expect((await BookRepo.getById(book.id)) !== null).assertTrue();
      } finally {
        await removeFixture(context, book);
      }
    });

    it('importsBeyondTheFormer100MiBLimitAndKeepsTheOriginalOnDeletion', 0, async () => {
      const context = await storageContext();
      const path: string = context.cacheDir + '/storage_source_' + Date.now() + '.txt';
      let book: Book | null = null;
      try {
        const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        try {
          const block: Uint8Array = new Uint8Array(128 * 1024);
          block.fill(65);
          for (let i: number = 0; i < 808; i++) {
            expect(await fs.write(file.fd, block.buffer)).assertEqual(block.length);
          }
        } finally {
          await fs.close(file);
        }
        book = await ImportService.importFromUri(context, path);
        expect(book.sizeBytes).assertEqual(101 * 1024 * 1024);
        expect(book.charCount).assertEqual(book.sizeBytes);
        const chapters: Chapter[] = await ChapterRepo.listByBook(book.id);
        expect(chapters[chapters.length - 1].byteEnd).assertEqual(book.sizeBytes);
        expect((await ImportService.readChapter(book, chapters[chapters.length - 1])).length)
          .assertEqual(chapters[chapters.length - 1].endOffset - chapters[chapters.length - 1].startOffset);
        await ImportService.deleteBook(context, book);
        expect(fs.accessSync(path)).assertTrue();
        expect(await BookRepo.getById(book.id)).assertNull();
        expect(MAX_SOURCE_BYTES > 1024 * 1024 * 1024).assertTrue();
      } finally {
        await removeFixture(context, book);
        if (fs.accessSync(path)) {
          await fs.unlink(path);
        }
      }
    });

    it('rejectsEmptyAndBinarySourcesWithoutPublishing', 0, async () => {
      const context = await storageContext();
      const path: string = context.cacheDir + '/storage_limit_' + Date.now() + '.txt';
      try {
        const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        await fs.close(file);
        for (let i: number = 0; i < 2; i++) {
          if (i > 0) {
            await fs.truncate(path, 128 * 1024);
          }
          let rejected: boolean = false;
          try {
            await ImportService.importFromUri(context, path);
          } catch (e) {
            rejected = true;
          }
          expect(rejected).assertTrue();
        }
      } finally {
        if (fs.accessSync(path)) {
          await fs.unlink(path);
        }
      }
    });

    it('cleansFailedImportsAndCrashOrphansWhileKeepingLiveCopies', 0, async () => {
      const context = await storageContext();
      let book: Book | null = null;
      const base: string = Db.booksDirectory(context) + '/book_' + Date.now() + '_99999.txt';
      const paths: string[] = [base, base + '.tmp'];
      try {
        book = await ImportService.importFromBytes(context, util.TextEncoder.create('utf-8').encodeInto('保留正文'), 'Storage Recovery');
        const before: string[] = await fs.listFile(Db.booksDirectory(context));
        let rejected: boolean = false;
        try {
          await ImportService.importFromBytes(context, new Uint8Array([65, 0, 66]), 'Storage Invalid');
        } catch (e) {
          rejected = true;
        }
        expect(rejected).assertTrue();
        const after: string[] = await fs.listFile(Db.booksDirectory(context));
        expect(after.sort().join(',')).assertEqual(before.sort().join(','));
        for (let i: number = 0; i < paths.length; i++) {
          const file = await fs.open(paths[i], fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
          await fs.close(file);
        }
        await ImportService.recover(context);
        expect(fs.accessSync(book.filePath)).assertTrue();
        expect(fs.accessSync(paths[0])).assertFalse();
        expect(fs.accessSync(paths[1])).assertFalse();
        await BookRepo.markDeleted(book.id);
        await ImportService.recover(context);
        expect(fs.accessSync(book.filePath)).assertFalse();
      } finally {
        await removeFixture(context, book);
        for (let i: number = 0; i < paths.length; i++) {
          if (fs.accessSync(paths[i])) {
            await fs.unlink(paths[i]);
          }
        }
      }
    });
  });
}
