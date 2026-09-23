import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { inspectPdfDocument, renderPdfCover } from './PdfWorker';
import { requireNativePdf } from './PdfCapability';
import { Book } from '../model/Models';
import { BookRepo } from '../data/BookRepo';
import { Db } from '../data/Db';
import { ImportActivity } from './ImportActivity';
import { CoverStore } from './CoverStore';

const PDF_COPY_CHUNK_BYTES: number = 128 * 1024;

/** Own only sandbox copies; the selected original is never modified or deleted. */
export class PdfImporter {
  static async importFromUri(context: common.UIAbilityContext, uri: string): Promise<Book> {
    requireNativePdf();
    const directory: string = Db.booksDirectory(context);
    if (!fs.accessSync(directory)) {
      fs.mkdirSync(directory);
    }
    const path: string = ImportActivity.reserve(directory, 'pdf');
    const temporary: string = path + '.tmp';
    let committed: boolean = false;
    let coverPath: string = '';
    try {
      const size: number = await PdfImporter.copyDocument(uri, temporary);
      const pages: number = await taskpool.execute(new taskpool.Task(inspectPdfDocument, temporary)) as number;
      try {
        const cover: ArrayBuffer = await taskpool.execute(new taskpool.Task(renderPdfCover, temporary)) as ArrayBuffer;
        coverPath = await CoverStore.stage(context, new Uint8Array(cover));
      } catch (e) { /* Optional thumbnail failure must not reject an otherwise readable PDF. */ }
      const book = new Book();
      book.title = PdfImporter.titleFromUri(uri);
      book.format = 'pdf';
      book.encoding = '';
      book.sizeBytes = size;
      // PDF progress is a zero-based page index, not a text character anchor.
      book.charCount = pages;
      book.coverColor = '#B85B4B';
      book.filePath = path;
      book.coverPath = coverPath;
      book.createdAt = Date.now();
      await fs.rename(temporary, path);
      book.id = await BookRepo.insert(book);
      committed = true;
      return book;
    } catch (e) {
      if (!committed) {
        await PdfImporter.removeIfPresent(temporary);
        try {
          if (!await BookRepo.hasLiveFile(path)) {
            await PdfImporter.removeIfPresent(path);
          }
        } catch (cleanupError) {
          // Keep a possibly committed file if the database cannot be queried.
        }
      }
      const detail: BusinessError = e as BusinessError;
      throw e instanceof Error ? e : new Error('PDF 导入失败：' + (detail.message || String(detail.code)));
    } finally {
      ImportActivity.remove(path);
      ImportActivity.remove(temporary);
      if (coverPath.length > 0) {
        CoverStore.finish(coverPath);
        await CoverStore.removeUnused(context, coverPath);
      }
    }
  }

  private static async copyDocument(uri: string, target: string): Promise<number> {
    const source = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const before = await fs.stat(source.fd);
      if (!Number.isSafeInteger(before.size) || before.size <= 0) {
        throw new Error('PDF 为空或无法获取文件大小');
      }
      const output = await fs.open(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        let copied: number = 0;
        const prefix: Uint8Array = new Uint8Array(5);
        while (copied < before.size) {
          const requested: number = Math.min(PDF_COPY_CHUNK_BYTES, before.size - copied);
          const buffer: ArrayBuffer = new ArrayBuffer(requested);
          const count: number = await fs.read(source.fd, buffer, { length: requested });
          if (count <= 0 || count > requested) {
            throw new Error('PDF 文件读取不完整，请重新选择文件');
          }
          const bytes: Uint8Array = new Uint8Array(buffer, 0, count);
          for (let index: number = 0; index < Math.min(count, 5 - copied); index++) {
            prefix[copied + index] = bytes[index];
          }
          if (copied < 5 && copied + count >= 5 &&
            (prefix[0] !== 37 || prefix[1] !== 80 || prefix[2] !== 68 || prefix[3] !== 70 || prefix[4] !== 45)) {
            throw new Error('文件内容不是有效的 PDF，仅修改扩展名无法导入');
          }
          let written: number = 0;
          while (written < count) {
            const remaining: Uint8Array = bytes.slice(written);
            const amount: number = await fs.write(output.fd, remaining.buffer);
            if (amount <= 0 || amount > remaining.length) {
              throw new Error('写入 PDF 副本失败，请检查可用空间');
            }
            written += amount;
          }
          copied += count;
        }
        if (copied < 5) {
          throw new Error('PDF 文件内容不完整');
        }
        const after = await fs.stat(source.fd);
        if (after.size !== before.size || after.mtime !== before.mtime) {
          throw new Error('PDF 在导入期间发生变化，请重新选择文件');
        }
        await fs.fsync(output.fd);
      } finally {
        await fs.close(output);
      }
      return before.size;
    } finally {
      await fs.close(source);
    }
  }

  private static async removeIfPresent(path: string): Promise<void> {
    try {
      if (fs.accessSync(path)) {
        await fs.unlink(path);
      }
    } catch (e) {
      // ImportService.recover retries incomplete copy cleanup on the next launch.
    }
  }

  private static titleFromUri(uri: string): string {
    let name: string = uri.substring(uri.lastIndexOf('/') + 1).split('?')[0];
    try {
      name = decodeURIComponent(name);
    } catch (e) {}
    return name.replace(/\.pdf$/i, '').replace(/[\u0000-\u001F]/g, '').trim().substring(0, 200) || '未命名 PDF';
  }
}
