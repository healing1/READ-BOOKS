import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Book } from '../model/Models';
import { Db } from '../data/Db';
import { BookRepo } from '../data/BookRepo';
import { EpubArchive } from './EpubArchive';
import { EpubDocument } from './EpubDocument';
import { ImportService } from './ImportService';
import { ImportActivity } from './ImportActivity';
import { EpubFonts } from './EpubFonts';

export class EpubSection {
  path: string = '';
  title: string = '';
  start: number = 0;
  end: number = 0;
  fixed: boolean = false;
}

/** The original ZIP is streamed into app storage; each document/resource is read on demand. */
export class EpubSource {
  static async copy(context: common.UIAbilityContext, uri: string): Promise<string> {
    const directory = Db.booksDirectory(context);
    if (!fs.accessSync(directory)) { fs.mkdirSync(directory); }
    const path: string = ImportActivity.reserve(directory, 'epub');
    try {
      const input = await fs.open(uri, fs.OpenMode.READ_ONLY);
      try {
        const before = await fs.stat(input.fd);
        const output = await fs.open(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try {
          let offset: number = 0;
          while (offset < before.size) {
            const buffer = new ArrayBuffer(Math.min(128 * 1024, before.size - offset));
            const count = await fs.read(input.fd, buffer);
            if (count <= 0) { throw new Error('原版 EPUB 读取不完整'); }
            let written: number = 0;
            while (written < count) {
              const part = new Uint8Array(buffer, written, count - written).slice();
              const n = await fs.write(output.fd, part.buffer);
              if (n <= 0) { throw new Error('原版 EPUB 保存失败，请检查存储空间'); }
              written += n;
            }
            offset += count;
          }
          const after = await fs.stat(input.fd);
          if (before.size !== after.size || before.mtime !== after.mtime) { throw new Error('原文件已变化，请重试'); }
          await fs.fsync(output.fd);
        } finally { await fs.close(output); }
      } finally { await fs.close(input); }
      await fs.rename(path + '.tmp', path);
      return path;
    } catch (e) {
      await EpubSource.discard(path);
      throw e instanceof Error ? e : new Error('无法保存原版 EPUB');
    }
  }

  static release(path: string): void { ImportActivity.remove(path); ImportActivity.remove(path + '.tmp'); }

  static async discard(path: string): Promise<void> {
    try { if (!await BookRepo.hasLiveFile(path) && fs.accessSync(path)) { await fs.unlink(path); } } catch (_) {}
    try { if (fs.accessSync(path + '.tmp')) { await fs.unlink(path + '.tmp'); } } catch (_) {}
    EpubSource.release(path);
  }

  /** Byte-for-byte text comparison prevents attaching another edition to existing anchors. */
  static async attach(context: common.UIAbilityContext, book: Book, uri: string): Promise<void> {
    const path: string = await EpubSource.copy(context, uri);
    try {
      const file = await fs.open(path, fs.OpenMode.READ_ONLY);
      const index: EpubSection[] = [];
      try {
        const stat = await fs.stat(file.fd);
        const archive = new EpubArchive(file.fd, stat.size, stat.mtime);
        await archive.initialize();
        const opf = EpubDocument.containerPath(await archive.readText('META-INF/container.xml', 1024 * 1024));
        const metadata = EpubDocument.package(await archive.readText(opf, 1024 * 1024), opf);
        await EpubFonts.inspect(archive, metadata);
        const encoder = util.TextEncoder.create('utf-8');
        let charOffset: number = 0;
        let byteOffset: number = 0;
        for (let i: number = 0; i < metadata.spine.length; i++) {
          const item = metadata.spine[i];
          const body = item.path.toLowerCase().endsWith('.svg') ? '' : EpubDocument.body(await archive.readText(item.path)).text;
          // Range reads are bounded to the same chunk size as the text reader.
          let consumed: number = 0;
          while (consumed < body.length) {
            let end: number = Math.min(body.length, consumed + 32000);
            if (end < body.length && body.charCodeAt(end - 1) >= 0xD800 && body.charCodeAt(end - 1) <= 0xDBFF) { end++; }
            // Comparison below uses characters and derives each UTF-8 range independently.
            const textPart = body.substring(consumed, end);
            const length = encoder.encodeInto(textPart).length;
            if (await ImportService.readUtf8Range(book.filePath, byteOffset, byteOffset + length) !== textPart) {
              throw new Error('这不是原先导入的同一版本，请选择原文件；不同版本请作为新书导入');
            }
            byteOffset += length;
            consumed = end;
            if (consumed >= body.length) { break; }
          }
          const section = new EpubSection();
          section.path = item.path; section.fixed = item.fixed; section.start = charOffset;
          charOffset += body.length; section.end = charOffset; section.title = '章节 ' + (i + 1);
          index.push(section);
        }
        if (charOffset !== book.charCount) { throw new Error('原文件版本不一致，未修改阅读记录'); }
        await archive.verify();
      } finally { await fs.close(file); }
      await BookRepo.attachEpub(book.id, path, JSON.stringify(index));
    } catch (e) { await EpubSource.discard(path); throw e instanceof Error ? e : new Error('无法补全 EPUB'); }
    finally { EpubSource.release(path); }
  }
}
