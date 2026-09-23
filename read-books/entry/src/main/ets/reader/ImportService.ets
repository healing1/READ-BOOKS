import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { EncodingDetector, StreamingTextNormalizer, StreamingTextValidator,
  StreamingUtf8Validator } from './EncodingDetector';
import { StreamingChapterDetector, utf8ByteLength } from './ChapterDetector';
import { BookRepo } from '../data/BookRepo';
import { ChapterRepo } from '../data/ChapterRepo';
import { Book, Chapter } from '../model/Models';
import { ImportActivity } from './ImportActivity';
import { Db } from '../data/Db';

const COVER_PALETTE: string[] = ['#007AFF', '#0064D6', '#AF3150', '#34C759', '#2F6B4A', '#3A3A3C', '#6E6E73', '#C66323'];
const IO_CHUNK_BYTES: number = 128 * 1024;
export const MAX_SOURCE_BYTES: number = Number.MAX_SAFE_INTEGER;
const MAX_STORED_BYTES: number = Number.MAX_SAFE_INTEGER;
const MAX_CHAPTER_READ_BYTES: number = 256 * 1024;

interface ImportSource {
  size: number;
  read(length: number): Promise<Uint8Array>;
  verify(): Promise<void>;
}

class MemoryImportSource implements ImportSource {
  size: number;
  private bytes: Uint8Array;
  private position: number = 0;

  constructor(bytes: Uint8Array) {
    this.bytes = bytes;
    this.size = bytes.length;
  }

  async read(length: number): Promise<Uint8Array> {
    const end: number = Math.min(this.position + length, this.size);
    const bytes: Uint8Array = this.bytes.subarray(this.position, end);
    this.position = end;
    return bytes;
  }

  async verify(): Promise<void> {}
}

class FileImportSource implements ImportSource {
  size: number;
  private fd: number;
  private modified: number;

  constructor(fd: number, size: number, modified: number) {
    this.fd = fd;
    this.size = size;
    this.modified = modified;
  }

  async read(length: number): Promise<Uint8Array> {
    const buffer: ArrayBuffer = new ArrayBuffer(length);
    const count: number = await fs.read(this.fd, buffer, { length: length });
    if (count <= 0 || count > length) {
      throw new Error('TXT 文件读取不完整，请重新选择文件');
    }
    return new Uint8Array(buffer, 0, count);
  }

  async verify(): Promise<void> {
    const stat = await fs.stat(this.fd);
    if (stat.size !== this.size || stat.mtime !== this.modified) {
      throw new Error('TXT 文件在读取期间发生变化，请重试');
    }
  }
}

/** Bounded decoding, normalized UTF-8 storage and character/byte chapter indexes. */
export class ImportService {
  private static indexJobs: Map<number, Promise<Chapter[]>> = new Map<number, Promise<Chapter[]>>();

  static async importFromBytes(context: common.UIAbilityContext, bytes: Uint8Array, title: string): Promise<Book> {
    ImportService.ensureSourceSize(bytes.length);
    return ImportService.importStream(context, new MemoryImportSource(bytes), EncodingDetector.detect(bytes), title);
  }

  static async importFromUri(context: common.UIAbilityContext, uri: string): Promise<Book> {
    let encoding: string = '';
    let size: number = 0;
    let modified: number = 0;
    const probe = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(probe.fd);
      size = stat.size;
      modified = stat.mtime;
      ImportService.ensureSourceSize(size);
      const source: FileImportSource = new FileImportSource(probe.fd, size, modified);
      const first: Uint8Array = new Uint8Array(Math.min(4, size));
      let prefixRead: number = 0;
      while (prefixRead < first.length) {
        const bytes: Uint8Array = await source.read(first.length - prefixRead);
        first.set(bytes, prefixRead);
        prefixRead += bytes.length;
      }
      encoding = EncodingDetector.detectBom(first, size);
      if (encoding.length === 0) {
        const validator: StreamingUtf8Validator = new StreamingUtf8Validator();
        validator.push(first);
        let read: number = first.length;
        while (read < size) {
          const bytes: Uint8Array = await source.read(Math.min(IO_CHUNK_BYTES, size - read));
          validator.push(bytes);
          read += bytes.length;
        }
        encoding = validator.finish() ? 'utf-8' : 'gb18030';
      }
      await source.verify();
    } finally {
      await fs.close(probe);
    }
    const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const source: FileImportSource = new FileImportSource(file.fd, size, modified);
      await source.verify();
      return await ImportService.importStream(context, source, encoding, ImportService.titleFromUri(uri));
    } finally {
      await fs.close(file);
    }
  }

  private static async importStream(context: common.UIAbilityContext, source: ImportSource,
    encoding: string, title: string): Promise<Book> {
    const booksDir: string = Db.booksDirectory(context);
    if (!fs.accessSync(booksDir)) {
      fs.mkdirSync(booksDir);
    }
    const path: string = ImportActivity.reserve(booksDir, 'txt');
    const tempPath: string = path + '.tmp';
    let committed: boolean = false;
    try {
      const detector: StreamingChapterDetector = new StreamingChapterDetector();
      const normalizer: StreamingTextNormalizer = new StreamingTextNormalizer();
      const validator: StreamingTextValidator = new StreamingTextValidator();
      const decoder = util.TextDecoder.create(encoding, { fatal: true, ignoreBOM: true });
      const encoder = util.TextEncoder.create('utf-8');
      let read: number = 0;
      let charCount: number = 0;
      let storedBytes: number = 0;
      const file = await fs.open(tempPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        while (read < source.size) {
          const bytes: Uint8Array = await source.read(Math.min(IO_CHUNK_BYTES, source.size - read));
          if (bytes.length === 0 || bytes.length > source.size - read) {
            throw new Error('TXT 文件读取不完整，请重新选择文件');
          }
          read += bytes.length;
          let decoded: string = '';
          try {
            decoded = decoder.decodeToString(bytes, { stream: read < source.size });
          } catch (e) {
            throw new Error('TXT 编码不完整或不支持，请另存为 UTF-8 后重试');
          }
          const text: string = normalizer.push(decoded, read === source.size);
          validator.push(text);
          detector.push(text);
          charCount += text.length;
          const normalized: Uint8Array = encoder.encodeInto(text);
          storedBytes += normalized.length;
          ImportService.ensureSize(storedBytes, MAX_STORED_BYTES, 'TXT 正文超出系统可表示范围');
          await ImportService.writeBytes(file.fd, normalized);
        }
        validator.finish();
        await source.verify();
        await fs.fsync(file.fd);
      } finally {
        await fs.close(file);
      }
      const chapters: Chapter[] = detector.finish();
      const book: Book = new Book();
      book.title = title.replace(/[\u0000-\u001F]/g, '').trim().substring(0, 200) || '未命名';
      book.sizeBytes = source.size;
      book.encoding = encoding;
      book.charCount = charCount;
      book.coverColor = COVER_PALETTE[Math.floor(Math.random() * COVER_PALETTE.length)];
      book.filePath = path;
      book.createdAt = Date.now();
      book.lastReadAt = 0;
      // A crash before the transaction leaves an unreferenced file which recover() removes.
      await fs.rename(tempPath, path);
      book.id = await BookRepo.insertWithChapters(book, chapters);
      committed = true;
      return book;
    } catch (e) {
      if (!committed) {
        await ImportService.removeIfPresent(tempPath);
        try {
          if (!await BookRepo.hasLiveFile(path)) {
            await ImportService.removeIfPresent(path);
          }
        } catch (cleanupError) {
          // Preserve a possible committed copy when the database is unavailable; recover() retries later.
        }
      }
      throw e instanceof Error ? e : new Error('导入失败');
    } finally {
      ImportActivity.remove(path);
      ImportActivity.remove(tempPath);
    }
  }

  /** Upgrades old books once, keeping their existing chapter and progress offsets. */
  static async ensureChapterIndex(book: Book, chapters: Chapter[]): Promise<Chapter[]> {
    if (chapters.length > 0 && chapters.every((chapter: Chapter) => chapter.byteStart >= 0 &&
      chapter.byteEnd >= chapter.byteStart)) {
      return chapters;
    }
    const pending: Promise<Chapter[]> | undefined = ImportService.indexJobs.get(book.id);
    if (pending !== undefined) {
      return pending;
    }
    const job: Promise<Chapter[]> = ImportService.buildChapterIndex(book, chapters);
    ImportService.indexJobs.set(book.id, job);
    try {
      return await job;
    } finally {
      if (ImportService.indexJobs.get(book.id) === job) {
        ImportService.indexJobs.delete(book.id);
      }
    }
  }

  private static async buildChapterIndex(book: Book, chapters: Chapter[]): Promise<Chapter[]> {
    let expectedStart: number = 0;
    for (let i: number = 0; i < chapters.length; i++) {
      const chapter: Chapter = chapters[i];
      if (chapter.startOffset !== expectedStart || chapter.endOffset <= chapter.startOffset ||
        chapter.endOffset - chapter.startOffset > 50001) {
        throw new Error('章节索引损坏，请重新导入这本书');
      }
      expectedStart = chapter.endOffset;
      chapter.byteStart = -1;
      chapter.byteEnd = -1;
    }
    if (chapters.length > 0 && expectedStart !== book.charCount) {
      throw new Error('章节长度与图书不一致，请重新导入这本书');
    }
    const file = await fs.open(book.filePath, fs.OpenMode.READ_ONLY);
    let count: number = 0;
    let bytesCount: number = 0;
    const detector: StreamingChapterDetector = new StreamingChapterDetector(book.id);
    try {
      const stat = await fs.stat(file.fd);
      ImportService.ensureSize(stat.size, MAX_STORED_BYTES, '图书副本过大');
      const source: FileImportSource = new FileImportSource(file.fd, stat.size, stat.mtime);
      const decoder = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true });
      let read: number = 0;
      let chapterIndex: number = 0;
      while (read < stat.size) {
        const bytes: Uint8Array = await source.read(Math.min(IO_CHUNK_BYTES, stat.size - read));
        read += bytes.length;
        const text: string = decoder.decodeToString(bytes, { stream: read < stat.size });
        if (chapters.length === 0) {
          detector.push(text);
        } else {
          let local: number = 0;
          while (chapterIndex < chapters.length) {
            const chapter: Chapter = chapters[chapterIndex];
            const boundary: number = chapter.byteStart < 0 ? chapter.startOffset : chapter.endOffset;
            if (boundary > count + text.length) {
              break;
            }
            const end: number = boundary - count;
            bytesCount += utf8ByteLength(text.substring(local, end));
            local = end;
            if (chapter.byteStart < 0) {
              chapter.byteStart = bytesCount;
            } else {
              chapter.byteEnd = bytesCount;
              chapterIndex++;
            }
          }
          bytesCount += utf8ByteLength(text.substring(local));
        }
        count += text.length;
      }
      await source.verify();
      if (count !== book.charCount || (chapters.length > 0 && bytesCount !== stat.size)) {
        throw new Error('图书副本发生变化，请重新导入这本书');
      }
    } finally {
      await fs.close(file);
    }
    if (chapters.length === 0) {
      const detected: Chapter[] = detector.finish();
      await ChapterRepo.insertAll(book.id, detected);
      return detected;
    }
    await ChapterRepo.updateByteIndex(book.id, chapters);
    return chapters;
  }

  static async readChapter(book: Book, chapter: Chapter): Promise<string> {
    if (chapter.byteStart < 0 || chapter.byteEnd < chapter.byteStart ||
      chapter.endOffset - chapter.startOffset > 50001) {
      throw new Error('章节索引尚未准备好，请重新打开图书');
    }
    const text: string = await ImportService.readUtf8Range(book.filePath, chapter.byteStart, chapter.byteEnd);
    if (text.length !== chapter.endOffset - chapter.startOffset) {
      throw new Error('章节正文读取不完整，请重新导入这本书');
    }
    return text;
  }

  static async readExcerpt(book: Book, offset: number, length: number): Promise<string> {
    if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(length) || length < 0 || length > 2048) {
      throw new Error('摘录位置或长度无效');
    }
    const chapters: Chapter[] = await ImportService.ensureChapterIndex(book, await ChapterRepo.listByBook(book.id));
    const end: number = Math.min(book.charCount, offset + length);
    let excerpt: string = '';
    for (let i: number = 0; i < chapters.length; i++) {
      const chapter: Chapter = chapters[i];
      if (chapter.startOffset >= end) {
        break;
      }
      if (chapter.endOffset <= offset) {
        continue;
      }
      const body: string = await ImportService.readChapter(book, chapter);
      excerpt += body.substring(Math.max(0, offset - chapter.startOffset), Math.min(body.length, end - chapter.startOffset));
    }
    const last: number = excerpt.charCodeAt(excerpt.length - 1);
    return last >= 0xD800 && last <= 0xDBFF ? excerpt.substring(0, excerpt.length - 1) : excerpt;
  }

  static async readUtf8Range(path: string, start: number, end: number): Promise<string> {
    ImportService.ensureSize(start, MAX_STORED_BYTES, '章节位置超出图书范围');
    ImportService.ensureSize(end - start, MAX_CHAPTER_READ_BYTES, '章节超出读取上限');
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(file.fd);
      if (end > stat.size) {
        throw new Error('TXT 文件读取不完整，请重新导入图书');
      }
      const decoder = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true });
      let count: number = 0;
      let text: string = '';
      fs.lseek(file.fd, start);
      while (count < end - start) {
        const size: number = Math.min(IO_CHUNK_BYTES, end - start - count);
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        const read: number = await fs.read(file.fd, buffer, { length: size });
        if (read <= 0 || read > size) {
          throw new Error('TXT 文件读取不完整，请重新导入图书');
        }
        count += read;
        text += decoder.decodeToString(new Uint8Array(buffer, 0, read), { stream: count < end - start });
      }
      return text;
    } finally {
      await fs.close(file);
    }
  }

  /** Retry file cleanup after interrupted imports or a committed deletion. */
  static async recover(context: common.UIAbilityContext): Promise<number> {
    const directory: string = Db.booksDirectory(context);
    if (!fs.accessSync(directory)) {
      return 0;
    }
    const books: Book[] = await BookRepo.listAll();
    const live: Set<string> = new Set<string>();
    books.forEach((book: Book) => { live.add(book.filePath); live.add(book.coverPath); live.add(book.sourcePath); });
    const names: string[] = await fs.listFile(directory);
    let failures: number = 0;
    for (let i: number = 0; i < names.length; i++) {
      const path: string = directory + '/' + names[i];
      if (/^book_[0-9]+_[0-9]+(\.(txt|pdf|epub)|_cover\.(png|jpg|jpeg))(\.tmp)?$/.test(names[i]) && !live.has(path) &&
        !ImportActivity.has(path)) {
        // Imports can commit after the initial snapshot; recheck before removing their final file.
        if (await BookRepo.hasLiveFile(path) || ImportActivity.has(path)) {
          continue;
        }
        if (!await ImportService.removeIfPresent(path)) {
          failures++;
        }
      }
    }
    return failures;
  }

  /** Only removes this app's sandbox copy; the original document URI is untouched. */
  static async deleteBook(context: common.UIAbilityContext, book: Book): Promise<void> {
    const expectedPrefix: string = Db.booksDirectory(context) + '/';
    const relativeName: string = book.filePath.substring(expectedPrefix.length);
    if (!book.filePath.startsWith(expectedPrefix) || !/^book_[0-9]+_[0-9]+\.(txt|pdf)$/.test(relativeName)) {
      throw new Error('图书副本路径无效，未删除文件');
    }
    if (book.coverPath.length > 0 && (!book.coverPath.startsWith(expectedPrefix) ||
      !/^book_[0-9]+_[0-9]+_cover\.(png|jpg|jpeg)$/.test(book.coverPath.substring(expectedPrefix.length)))) {
      throw new Error('图书封面路径无效，未删除文件');
    }
    // Fetch the latest cover in the same transaction as the tombstone; the UI's Book may be stale.
    const currentCover: string = await BookRepo.markDeleted(book.id);
    const validCurrentCover: boolean = currentCover.length === 0 || (currentCover.startsWith(expectedPrefix) &&
      /^book_[0-9]+_[0-9]+_cover\.(png|jpg|jpeg)$/.test(currentCover.substring(expectedPrefix.length)));
    const bodyRemoved: boolean = await ImportService.removeIfPresent(book.filePath);
    const coverRemoved: boolean = validCurrentCover && (currentCover.length === 0 || await ImportService.removeIfPresent(currentCover));
    // Source attachment can race with deletion; recovery also rechecks every unreferenced EPUB.
    if (book.sourcePath.startsWith(expectedPrefix) && /^book_[0-9]+_[0-9]+\.epub$/.test(book.sourcePath.substring(expectedPrefix.length)) &&
      !await BookRepo.hasLiveFile(book.sourcePath)) { await ImportService.removeIfPresent(book.sourcePath); }
    if (!bodyRemoved || !coverRemoved) {
      throw new Error('图书已移出书架，本地副本将在下次启动时继续清理');
    }
  }

  private static async removeIfPresent(path: string): Promise<boolean> {
    try {
      if (fs.accessSync(path)) {
        await fs.unlink(path);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  private static async writeBytes(fd: number, bytes: Uint8Array): Promise<void> {
    let offset: number = 0;
    while (offset < bytes.length) {
      const remaining: Uint8Array = offset === 0 ? bytes : bytes.slice(offset);
      const written: number = await fs.write(fd, remaining.buffer);
      if (written <= 0 || written > remaining.length) {
        throw new Error('写入 TXT 文件失败');
      }
      offset += written;
    }
  }

  /** Bounded compatibility helpers for small fixtures, not used by Reader. */
  static readAllBytes(fd: number, maxBytes: number = MAX_CHAPTER_READ_BYTES,
    sizeError: string = 'TXT 文件过大'): Uint8Array {
    const stat = fs.statSync(fd);
    ImportService.ensureSize(stat.size, maxBytes, sizeError);
    const out: Uint8Array = new Uint8Array(stat.size);
    let total: number = 0;
    while (total < out.length) {
      const size: number = Math.min(IO_CHUNK_BYTES, out.length - total);
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      const read: number = fs.readSync(fd, buffer, { length: size });
      if (read <= 0 || read > size) {
        throw new Error('TXT 文件读取不完整，请重新选择文件');
      }
      out.set(new Uint8Array(buffer, 0, read), total);
      total += read;
    }
    const after = fs.statSync(fd);
    if (after.size !== stat.size || after.mtime !== stat.mtime) {
      throw new Error('TXT 文件在读取期间发生变化，请重试');
    }
    return out;
  }

  static async readTextFile(path: string): Promise<string> {
    const stat = await fs.stat(path);
    return ImportService.readUtf8Range(path, 0, stat.size);
  }

  private static ensureSourceSize(size: number): void {
    ImportService.ensureSize(size, MAX_SOURCE_BYTES, 'TXT 文件大小超出系统可表示范围');
    if (size === 0) {
      throw new Error('TXT 文件为空');
    }
  }

  private static ensureSize(size: number, maxBytes: number, message: string): void {
    if (!Number.isSafeInteger(size) || size < 0 || !Number.isSafeInteger(maxBytes) || maxBytes < 0) {
      throw new Error('无法获取有效的 TXT 文件大小');
    }
    if (size > maxBytes) {
      throw new Error(message);
    }
  }

  private static titleFromUri(uri: string): string {
    let name: string = uri.substring(uri.lastIndexOf('/') + 1).split('?')[0];
    try {
      name = decodeURIComponent(name);
    } catch (e) {}
    if (name.toLowerCase().endsWith('.txt')) {
      name = name.substring(0, name.length - 4);
    }
    return name.length > 0 ? name : '未命名';
  }
}
