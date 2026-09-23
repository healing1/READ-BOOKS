import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { Book } from '../model/Models';
import { BookRepo } from '../data/BookRepo';
import { CoverStore } from './CoverStore';
import { EpubImporter } from './EpubImporter';
import { renderPdfCover } from './PdfWorker';
import { requireNativePdf, supportsNativePdf } from './PdfCapability';

export class CoverService {
  static async fromImage(context: common.UIAbilityContext, book: Book, uri: string): Promise<void> {
    await CoverStore.replace(context, book.id, book.coverPath, await CoverStore.readImage(uri));
  }

  static async fromEpub(context: common.UIAbilityContext, book: Book, uri: string): Promise<void> {
    const bytes: Uint8Array | null = await EpubImporter.readCoverFromUri(uri);
    if (bytes === null) { throw new Error('这本 EPUB 没有可用的 PNG/JPEG 封面，可以选择一张图片'); }
    await CoverStore.replace(context, book.id, book.coverPath, bytes);
  }

  static async fromPdf(context: common.UIAbilityContext, book: Book): Promise<void> {
    requireNativePdf();
    const bytes: ArrayBuffer = await taskpool.execute(new taskpool.Task(renderPdfCover, book.filePath)) as ArrayBuffer;
    await CoverStore.replace(context, book.id, book.coverPath, new Uint8Array(bytes));
  }

  static async useText(context: common.UIAbilityContext, book: Book): Promise<void> {
    if (book.format !== 'txt') { throw new Error('此操作仅适用于 TXT 图书'); }
    await BookRepo.replaceCover(book.id, '', book.coverPath);
    await CoverStore.removeUnused(context, book.coverPath);
  }

  /** One worker at a time; never read a user's external files or replace an existing custom cover. */
  static async repairMissingPdfs(context: common.UIAbilityContext, books: Book[], updated: () => Promise<void>): Promise<void> {
    if (!supportsNativePdf()) { return; }
    for (let i: number = 0; i < books.length; i++) {
      const book: Book = books[i];
      try {
        if (book.format !== 'pdf' || (book.coverPath.length > 0 && fs.accessSync(book.coverPath))) { continue; }
        await CoverService.fromPdf(context, book);
        await updated();
      } catch (e) { /* Keep the typeset cover; the book menu offers an explicit retry. */ }
    }
  }
}
