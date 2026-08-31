import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { EncodingDetector } from './EncodingDetector';
import { ChapterDetector } from './ChapterDetector';
import { BookRepo } from '../data/BookRepo';
import { ChapterRepo } from '../data/ChapterRepo';
import { Book } from '../model/Models';

/** 封面色板 —— 品牌蓝系 + 中性，docs/DESIGN.md §4.5 */
const COVER_PALETTE: string[] = ['#007AFF', '#0064D6', '#004FAD', '#34C759', '#2F6B4A', '#3A3A3C', '#6E6E73', '#5E5CE6'];

/**
 * 导入管线 —— docs/DESIGN.md §5.1
 * 选文件 → 分块读字节 → 编码检测 → 归一化 → 写沙箱 UTF-8 → 章节 → 入库
 */
export class ImportService {
  private static seq: number = 0;

  static async importFromBytes(context: common.UIAbilityContext, bytes: Uint8Array, title: string): Promise<Book> {
    const encoding: string = EncodingDetector.detect(bytes);
    const raw: string = EncodingDetector.decode(bytes, encoding);
    const text: string = raw.replace(/\r\n/g, '\n').replace(/\r/g, '\n');

    const booksDir: string = context.filesDir + '/books';
    if (!fs.accessSync(booksDir)) {
      fs.mkdirSync(booksDir);
    }
    const fileName: string = 'book_' + Date.now() + '_' + (ImportService.seq++) + '.txt';
    const path: string = booksDir + '/' + fileName;
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, text);
    fs.closeSync(file);

    const book = new Book();
    book.title = title;
    book.format = 'txt';
    book.sizeBytes = bytes.length;
    book.encoding = encoding;
    book.charCount = text.length;
    book.coverColor = COVER_PALETTE[Math.floor(Math.random() * COVER_PALETTE.length)];
    book.filePath = path;
    book.createdAt = Date.now();
    book.lastReadAt = Date.now();
    const id: number = await BookRepo.insert(book);
    book.id = id;

    const chapters = ChapterDetector.detect(text, id);
    await ChapterRepo.insertAll(id, chapters);
    return book;
  }

  static async importFromUri(context: common.UIAbilityContext, uri: string): Promise<Book | null> {
    try {
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const bytes: Uint8Array = ImportService.readAllBytes(src.fd);
      fs.closeSync(src);
      const title: string = ImportService.titleFromUri(uri);
      return await ImportService.importFromBytes(context, bytes, title);
    } catch (e) {
      return null;
    }
  }

  static async readTextFile(path: string): Promise<string> {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    const bytes: Uint8Array = ImportService.readAllBytes(file.fd);
    fs.closeSync(file);
    return EncodingDetector.decode(bytes, 'utf-8');
  }

  /** 流式分块读取（1MB/块）—— docs/DESIGN.md §5.4 前置 */
  static readAllBytes(fd: number): Uint8Array {
    const stat = fs.statSync(fd);
    const size: number = stat.size;
    const CHUNK: number = 1024 * 1024;
    const chunks: Uint8Array[] = [];
    let total: number = 0;
    let done: boolean = false;
    while (!done) {
      const buf = new ArrayBuffer(CHUNK);
      const read: number = fs.readSync(fd, buf, { length: CHUNK });
      if (read <= 0) {
        break;
      }
      chunks.push(new Uint8Array(buf).subarray(0, read));
      total += read;
      if (read < CHUNK) {
        done = true;
      }
    }
    const out = new Uint8Array(total);
    let offset: number = 0;
    for (let i = 0; i < chunks.length; i++) {
      out.set(chunks[i], offset);
      offset += chunks[i].length;
    }
    return out;
  }

  private static titleFromUri(uri: string): string {
    let name: string = uri;
    const slash: number = name.lastIndexOf('/');
    if (slash >= 0) {
      name = name.substring(slash + 1);
    }
    const query: number = name.indexOf('?');
    if (query >= 0) {
      name = name.substring(0, query);
    }
    try {
      name = decodeURIComponent(name);
    } catch (e) {
      // 保留原名
    }
    if (name.length > 4 && name.substring(name.length - 4).toLowerCase() === '.txt') {
      name = name.substring(0, name.length - 4);
    }
    return name.length > 0 ? name : '未命名';
  }
}
