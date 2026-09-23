import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Book, Chapter, MAX_CHAPTERS_PER_BOOK } from '../model/Models';
import { BookRepo } from '../data/BookRepo';
import { Db } from '../data/Db';
import { ImportActivity } from './ImportActivity';
import { EpubArchive, EPUB_EXPANDED_LIMIT } from './EpubArchive';
import { EpubBody, EpubDocument, EpubPackage } from './EpubDocument';
import { utf8ByteLength } from './ChapterDetector';
import { CoverStore } from './CoverStore';
import { EpubSection, EpubSource } from './EpubSource';
import { EpubFonts } from './EpubFonts';

const METADATA_BYTES: number = 1024 * 1024;
const COVER_BYTES: number = 4 * 1024 * 1024;

/** Preserve EPUB spine titles; split only very long documents at safe UTF-16 boundaries. */
export function appendEpubChapters(chapters: Chapter[], text: string, title: string,
  charStart: number, byteStart: number): void {
  let position: number = 0;
  let bytes: number = byteStart;
  let part: number = 1;
  while (position < text.length) {
    if (chapters.length >= MAX_CHAPTERS_PER_BOOK) {
      throw new Error('EPUB 章节数量不能超过 10000');
    }
    let end: number = Math.min(text.length, position + 50000);
    if (end < text.length && text.charCodeAt(end - 1) >= 0xD800 && text.charCodeAt(end - 1) <= 0xDBFF &&
      text.charCodeAt(end) >= 0xDC00 && text.charCodeAt(end) <= 0xDFFF) {
      end++;
    }
    const chapter: Chapter = new Chapter();
    chapter.idx = chapters.length;
    chapter.title = part === 1 ? title : title + '（续 ' + part + '）';
    chapter.startOffset = charStart + position;
    chapter.endOffset = charStart + end;
    chapter.byteStart = bytes;
    bytes += utf8ByteLength(text.substring(position, end));
    chapter.byteEnd = bytes;
    chapters.push(chapter);
    position = end;
    part++;
  }
}

/** Sniff local cover bytes and reject extreme pixel dimensions before handing them to Image. */
export function epubCoverExtension(bytes: Uint8Array): string {
  let width: number = 0;
  let height: number = 0;
  let extension: string = '';
  if (bytes.length >= 33 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47 &&
    bytes[4] === 13 && bytes[5] === 10 && bytes[6] === 26 && bytes[7] === 10) {
    const view: DataView = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    if (view.getUint32(8) !== 13 || view.getUint32(12) !== 0x49484452) {
      return '';
    }
    width = view.getUint32(16);
    height = view.getUint32(20);
    extension = 'png';
  } else if (bytes.length > 4 && bytes[0] === 0xFF && bytes[1] === 0xD8) {
    let offset: number = 2;
    while (offset + 4 < bytes.length) {
      if (bytes[offset] !== 0xFF) {
        return '';
      }
      while (offset < bytes.length && bytes[offset] === 0xFF) { offset++; }
      const marker: number = bytes[offset++];
      if (marker === 0xD9 || marker === 0xDA || offset + 2 > bytes.length) { break; }
      if (marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) { continue; }
      const length: number = bytes[offset] * 256 + bytes[offset + 1];
      if (length < 2 || offset + length > bytes.length) { return ''; }
      if ((marker >= 0xC0 && marker <= 0xC3) || (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) || (marker >= 0xCD && marker <= 0xCF)) {
        if (length < 8) { return ''; }
        height = bytes[offset + 3] * 256 + bytes[offset + 4];
        width = bytes[offset + 5] * 256 + bytes[offset + 6];
        extension = 'jpg';
        break;
      }
      offset += length;
    }
  }
  return width > 0 && height > 0 && width <= 8192 && height <= 8192 && width * height <= 16000000 ? extension : '';
}

/** Imports DRM-free reflowable EPUB 2/3 as bounded UTF-8 chapter storage, preserving source files. */
export class EpubImporter {
  static isActivePath(path: string): boolean {
    return ImportActivity.has(path);
  }

  /** Re-read only cover metadata from an original EPUB; never replace text, progress or bookmarks. */
  static async readCoverFromUri(uri: string): Promise<Uint8Array | null> {
    const source = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(source.fd);
      const archive: EpubArchive = new EpubArchive(source.fd, stat.size, stat.mtime);
      await archive.initialize();
      const opfPath: string = EpubDocument.containerPath(await archive.readText('META-INF/container.xml', METADATA_BYTES));
      const metadata: EpubPackage = EpubDocument.package(await archive.readText(opfPath, METADATA_BYTES), opfPath);
      await EpubFonts.inspect(archive, metadata);
      const cover: Uint8Array | null = await EpubImporter.findCover(archive, metadata);
      await archive.verify();
      return cover;
    } finally { await fs.close(source); }
  }

  private static async findCover(archive: EpubArchive, metadata: EpubPackage): Promise<Uint8Array | null> {
    let imageAttempts: number = 0;
    const visited: Set<string> = new Set<string>();
    for (let i: number = 0; i < metadata.coverCandidates.length && imageAttempts < 12; i++) {
      const path: string = metadata.coverCandidates[i];
      if (!archive.has(path)) { continue; }
      let paths: string[] = [path];
      if (/\.(xhtml|html|htm|svg)$/i.test(path)) {
        try { paths = EpubDocument.coverImages(await archive.readText(path, METADATA_BYTES), path); }
        catch (e) { continue; }
      }
      for (let j: number = 0; j < paths.length && imageAttempts < 12; j++) {
        if (visited.has(paths[j]) || !archive.has(paths[j])) { continue; }
        visited.add(paths[j]);
        imageAttempts++;
        try {
          const bytes: Uint8Array = await archive.readEntry(paths[j], COVER_BYTES);
          if (epubCoverExtension(bytes).length > 0) { return await CoverStore.normalize(bytes); }
        } catch (e) { /* A bad optional cover must not discard a readable book. */ }
      }
    }
    return null;
  }

  static async importFromUri(context: common.UIAbilityContext, uri: string): Promise<Book> {
    const source = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(source.fd);
      const archive: EpubArchive = new EpubArchive(source.fd, stat.size, stat.mtime);
      await archive.initialize();
      const opfPath: string = EpubDocument.containerPath(await archive.readText('META-INF/container.xml', METADATA_BYTES));
      const metadata: EpubPackage = EpubDocument.package(await archive.readText(opfPath, METADATA_BYTES), opfPath);
      await EpubFonts.inspect(archive, metadata);
      let titles: Map<string, string> = new Map<string, string>();
      if (metadata.navigationPath.length > 0 && archive.has(metadata.navigationPath)) {
        // An invalid optional table of contents cannot reorder or silently drop the mandatory spine.
        try {
          titles = EpubDocument.navigation(await archive.readText(metadata.navigationPath, METADATA_BYTES), metadata.navigationPath);
        } catch (e) {}
      }
      return await EpubImporter.publish(context, archive, metadata, titles, uri);
    } finally {
      await fs.close(source);
    }
  }

  private static async publish(context: common.UIAbilityContext, archive: EpubArchive, metadata: EpubPackage,
    titles: Map<string, string>, uri: string): Promise<Book> {
    const directory: string = Db.booksDirectory(context);
    if (!fs.accessSync(directory)) {
      fs.mkdirSync(directory);
    }
    const path: string = ImportActivity.reserve(directory, 'txt');
    const temporary: string = path + '.tmp';
    let coverPath: string = '';
    let sourcePath: string = '';
    let committed: boolean = false;
    try {
      const file = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const encoder = util.TextEncoder.create('utf-8');
      const chapters: Chapter[] = [];
      const sections: EpubSection[] = [];
      let chars: number = 0;
      let bytes: number = 0;
      try {
        for (let i: number = 0; i < metadata.spine.length; i++) {
          const itemPath: string = metadata.spine[i].path;
          const body: EpubBody = itemPath.toLowerCase().endsWith('.svg') ? new EpubBody('', '') :
            EpubDocument.body(await archive.readText(itemPath));
          if (body.text.length === 0) {
            // A source locator exists even when the publisher's page contains only an illustration.
            body.text = '\uFFFC\n\n';
          }
          const title: string = titles.get(itemPath) || body.title || '章节 ' + (i + 1);
          const encoded: Uint8Array = encoder.encodeInto(body.text);
          if (bytes + encoded.length > EPUB_EXPANDED_LIMIT) {
            throw new Error('EPUB 正文超出系统可表示范围');
          }
          const section = new EpubSection();
          section.path = itemPath; section.title = title; section.start = chars;
          section.end = chars + body.text.length; section.fixed = metadata.spine[i].fixed;
          sections.push(section);
          appendEpubChapters(chapters, body.text, title, chars, bytes);
          await EpubImporter.write(file.fd, encoded);
          chars += body.text.length;
          bytes += encoded.length;
        }
        if (chars === 0) {
          throw new Error('EPUB 没有可阅读的内容');
        }
        await archive.verify();
        await fs.fsync(file.fd);
      } finally {
        await fs.close(file);
      }
      {
        try {
          const cover: Uint8Array | null = await EpubImporter.findCover(archive, metadata);
          if (cover !== null) {
            const extension: string = epubCoverExtension(cover);
            coverPath = path.substring(0, path.length - 4) + '_cover.' + extension;
            ImportActivity.add(coverPath);
            ImportActivity.add(coverPath + '.tmp');
            const coverFile = await fs.open(coverPath + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
            try {
              await EpubImporter.write(coverFile.fd, cover);
              await fs.fsync(coverFile.fd);
            } finally {
              await fs.close(coverFile);
            }
            await fs.rename(coverPath + '.tmp', coverPath);
          }
        } catch (e) {
          if (coverPath.length > 0) {
            await EpubImporter.remove(coverPath + '.tmp');
            await EpubImporter.remove(coverPath);
            ImportActivity.remove(coverPath + '.tmp');
            ImportActivity.remove(coverPath);
            coverPath = '';
          }
        }
      }
      await archive.verify();
      const book: Book = new Book();
      book.title = metadata.title || EpubImporter.titleFromUri(uri);
      book.author = metadata.author;
      book.format = 'epub';
      book.encoding = 'utf-8';
      book.sizeBytes = archive.size;
      book.charCount = chars;
      book.filePath = path;
      sourcePath = await EpubSource.copy(context, uri);
      await archive.verify();
      book.sourcePath = sourcePath;
      book.epubIndex = JSON.stringify(sections);
      book.coverPath = coverPath;
      book.coverColor = '#806554';
      book.createdAt = Date.now();
      await fs.rename(temporary, path);
      book.id = await BookRepo.insertWithChapters(book, chapters);
      committed = true;
      return book;
    } catch (e) {
      if (!committed) {
        if (sourcePath) { await EpubSource.discard(sourcePath); }
        await EpubImporter.remove(temporary);
        try {
          if (!await BookRepo.hasLiveFile(path)) {
            await EpubImporter.remove(path);
            if (coverPath.length > 0) {
              await EpubImporter.remove(coverPath);
              await EpubImporter.remove(coverPath + '.tmp');
            }
          }
        } catch (cleanupError) {
          // Recovery handles unreferenced paths once the database is available again.
        }
      }
      throw e instanceof Error ? e : new Error('EPUB 导入失败');
    } finally {
      if (sourcePath) { EpubSource.release(sourcePath); }
      ImportActivity.remove(path);
      ImportActivity.remove(temporary);
      if (coverPath.length > 0) {
        ImportActivity.remove(coverPath);
        ImportActivity.remove(coverPath + '.tmp');
      }
    }
  }

  private static async write(fd: number, bytes: Uint8Array): Promise<void> {
    let offset: number = 0;
    while (offset < bytes.length) {
      const chunk: Uint8Array = bytes.slice(offset, Math.min(offset + 128 * 1024, bytes.length));
      const written: number = await fs.write(fd, chunk.buffer);
      if (written <= 0 || written > chunk.length) {
        throw new Error('写入 EPUB 正文失败');
      }
      offset += written;
    }
  }

  private static async remove(path: string): Promise<void> {
    try {
      if (fs.accessSync(path)) { await fs.unlink(path); }
    } catch (e) {}
  }

  private static titleFromUri(uri: string): string {
    let name: string = uri.substring(uri.lastIndexOf('/') + 1).split('?')[0];
    try { name = decodeURIComponent(name); } catch (e) {}
    return name.replace(/\.epub$/i, '').replace(/[\u0000-\u001f]/g, '').trim().substring(0, 200) || '未命名 EPUB';
  }
}
