import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';

export const EPUB_ARCHIVE_LIMIT: number = Number.MAX_SAFE_INTEGER;
export const EPUB_EXPANDED_LIMIT: number = Number.MAX_SAFE_INTEGER;
export const EPUB_DOCUMENT_LIMIT: number = 8 * 1024 * 1024;
const DIRECTORY_LIMIT: number = 4 * 1024 * 1024;
const ENTRY_LIMIT: number = 10000;

export class EpubEntry {
  name: string = '';
  flags: number = 0;
  method: number = 0;
  crc: number = 0;
  compressed: number = 0;
  expanded: number = 0;
  offset: number = 0;
  nextOffset: number = 0;
}

/** Paths are ZIP identifiers, never paths passed to a filesystem extraction API. */
export function safeEpubPath(path: string): string {
  if (path.length === 0 || path.length > 1024 || /^[\/]/.test(path) || /[\\:\u0000-\u001f\u007f]/.test(path)) {
    throw new Error('EPUB 含不安全的资源路径');
  }
  const parts: string[] = path.split('/');
  for (let i: number = 0; i < parts.length; i++) {
    if (parts[i] === '..' || parts[i] === '.' || (parts[i] === '' && i !== parts.length - 1)) {
      throw new Error('EPUB 含不安全的资源路径');
    }
  }
  return path;
}

/** Resolve URL-relative package links without allowing an escape from the ZIP root. */
export function resolveEpubPath(baseFile: string, href: string): string {
  let decoded: string = '';
  try {
    decoded = decodeURIComponent(href.split('#')[0]);
  } catch (e) {
    throw new Error('EPUB 资源地址编码无效');
  }
  if (decoded.length === 0) {
    return safeEpubPath(baseFile);
  }
  if (/^[\/]/.test(decoded) || /[\\:?\u0000-\u001f\u007f]/.test(decoded)) {
    throw new Error('EPUB 不支持外部资源地址');
  }
  const stack: string[] = baseFile.indexOf('/') < 0 ? [] : baseFile.substring(0, baseFile.lastIndexOf('/')).split('/');
  const parts: string[] = decoded.split('/');
  for (let i: number = 0; i < parts.length; i++) {
    if (parts[i] === '..') {
      if (stack.length === 0) {
        throw new Error('EPUB 资源地址越界');
      }
      stack.pop();
    } else if (parts[i] !== '.') {
      stack.push(parts[i]);
    }
  }
  return safeEpubPath(stack.join('/'));
}

const CRC_TABLE: Uint32Array = new Uint32Array(256);
for (let value: number = 0; value < 256; value++) {
  let remainder: number = value;
  for (let bit: number = 0; bit < 8; bit++) { remainder = (remainder >>> 1) ^ ((remainder & 1) !== 0 ? 0xEDB88320 : 0); }
  CRC_TABLE[value] = remainder >>> 0;
}

export function epubCrc32(bytes: Uint8Array): number {
  let crc: number = 0xFFFFFFFF;
  for (let i: number = 0; i < bytes.length; i++) {
    crc = (crc >>> 8) ^ CRC_TABLE[(crc ^ bytes[i]) & 0xFF];
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

/** Bounded ZIP central-directory reader. Never decompresses an archive to a directory. */
export class EpubArchive {
  readonly size: number;
  private fd: number;
  private modified: number;
  private entries: Map<string, EpubEntry> = new Map<string, EpubEntry>();

  constructor(fd: number, size: number, modified: number) {
    this.fd = fd;
    this.size = size;
    this.modified = modified;
  }

  async initialize(): Promise<void> {
    if (!Number.isSafeInteger(this.size) || this.size < 22 || this.size > EPUB_ARCHIVE_LIMIT) {
      throw new Error('EPUB 文件为空、损坏或大小无效');
    }
    const tailOffset: number = Math.max(0, this.size - 65557);
    const tail: Uint8Array = await this.readAt(tailOffset, this.size - tailOffset);
    const tailView: DataView = new DataView(tail.buffer);
    let end: number = -1;
    for (let i: number = tail.length - 22; i >= 0; i--) {
      if (tailView.getUint32(i, true) === 0x06054B50 && i + 22 + tailView.getUint16(i + 20, true) === tail.length) {
        end = i;
        break;
      }
    }
    if (end < 0) {
      throw new Error('EPUB ZIP 目录损坏');
    }
    const count: number = tailView.getUint16(end + 10, true);
    const length: number = tailView.getUint32(end + 12, true);
    const offset: number = tailView.getUint32(end + 16, true);
    if (tailView.getUint16(end + 4, true) !== 0 || tailView.getUint16(end + 6, true) !== 0 ||
      tailView.getUint16(end + 8, true) !== count || count === 0 || count > ENTRY_LIMIT ||
      length > DIRECTORY_LIMIT || length < count * 46 || offset + length !== tailOffset + end) {
      throw new Error('不支持分卷、ZIP64 或超大目录的 EPUB');
    }
    const bytes: Uint8Array = await this.readAt(offset, length);
    const view: DataView = new DataView(bytes.buffer);
    const ordered: EpubEntry[] = [];
    let position: number = 0;
    let expanded: number = 0;
    for (let i: number = 0; i < count; i++) {
      if (position + 46 > length || view.getUint32(position, true) !== 0x02014B50) {
        throw new Error('EPUB ZIP 目录损坏');
      }
      const entry: EpubEntry = new EpubEntry();
      entry.flags = view.getUint16(position + 8, true);
      entry.method = view.getUint16(position + 10, true);
      entry.crc = view.getUint32(position + 16, true);
      entry.compressed = view.getUint32(position + 20, true);
      entry.expanded = view.getUint32(position + 24, true);
      const nameLength: number = view.getUint16(position + 28, true);
      const extraLength: number = view.getUint16(position + 30, true);
      const commentLength: number = view.getUint16(position + 32, true);
      entry.offset = view.getUint32(position + 42, true);
      if (nameLength === 0 || nameLength > 4096 || position + 46 + nameLength + extraLength + commentLength > length ||
        (entry.flags & 0x2041) !== 0 || (entry.method !== 0 && entry.method !== 8) ||
        view.getUint16(position + 34, true) !== 0 || entry.offset + 30 + entry.compressed > offset ||
        entry.expanded === 0xFFFFFFFF || (entry.method === 0 && entry.expanded !== entry.compressed)) {
        throw new Error('EPUB 包含加密、损坏或不支持的 ZIP 资源');
      }
      // Non-UTF-8 legacy names are rejected instead of guessed; ASCII names work with either flag.
      entry.name = safeEpubPath(util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(
        bytes.subarray(position + 46, position + 46 + nameLength)));
      if (this.entries.has(entry.name)) {
        throw new Error('EPUB ZIP 中存在重复资源');
      }
      const unixMode: number = view.getUint32(position + 38, true) >>> 16;
      if ((unixMode & 0xF000) === 0xA000) {
        throw new Error('EPUB 不允许符号链接');
      }
      expanded += entry.expanded;
      if (expanded > EPUB_EXPANDED_LIMIT || (entry.expanded > 1024 * 1024 &&
        entry.expanded > Math.max(1, entry.compressed) * 1000)) {
        throw new Error('EPUB 解压内容过大或压缩率异常');
      }
      this.entries.set(entry.name, entry);
      ordered.push(entry);
      position += 46 + nameLength + extraLength + commentLength;
    }
    if (position !== length) {
      throw new Error('EPUB ZIP 目录长度无效');
    }
    ordered.sort((a: EpubEntry, b: EpubEntry) => a.offset - b.offset);
    for (let i: number = 0; i < ordered.length; i++) {
      ordered[i].nextOffset = i + 1 < ordered.length ? ordered[i + 1].offset : offset;
      if (ordered[i].offset + 30 + ordered[i].compressed > ordered[i].nextOffset) {
        throw new Error('EPUB ZIP 资源互相重叠');
      }
      const lower: string = ordered[i].name.toLowerCase();
      if (lower === 'meta-inf/rights.xml') {
        throw new Error('暂不支持受 DRM 保护或含加密资源的 EPUB');
      }
    }
    const mime: EpubEntry | undefined = this.entries.get('mimetype');
    if (mime === undefined || mime.method !== 0 || mime.offset !== 0 ||
      await this.readText('mimetype', 64) !== 'application/epub+zip') {
      throw new Error('文件不是有效的 EPUB');
    }
    await this.verify();
  }

  has(path: string): boolean {
    return this.entries.has(path);
  }

  async readText(path: string, limit: number = EPUB_DOCUMENT_LIMIT): Promise<string> {
    const bytes: Uint8Array = await this.readEntry(path, limit);
    return EpubArchive.decodeText(bytes);
  }

  static decodeText(bytes: Uint8Array): string {
    let encoding: string = 'utf-8';
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      encoding = 'utf-16le';
    } else if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      encoding = 'utf-16be';
    }
    try {
      const text: string = util.TextDecoder.create(encoding, { fatal: true, ignoreBOM: true }).decodeToString(bytes);
      if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(text)) {
        throw new Error('binary');
      }
      return text.replace(/^\uFEFF/, '');
    } catch (e) {
      throw new Error('EPUB 正文不是有效的 UTF-8 / UTF-16 文本');
    }
  }

  async readEntry(path: string, limit: number): Promise<Uint8Array> {
    const entry: EpubEntry | undefined = this.entries.get(safeEpubPath(path));
    if (entry === undefined || entry.expanded > limit || entry.compressed > limit + 65536) {
      throw new Error('EPUB 缺少资源或单个资源超过读取上限');
    }
    const header: Uint8Array = await this.readAt(entry.offset, 30);
    const view: DataView = new DataView(header.buffer);
    const nameLength: number = view.getUint16(26, true);
    const extraLength: number = view.getUint16(28, true);
    const dataOffset: number = entry.offset + 30 + nameLength + extraLength;
    if (view.getUint32(0, true) !== 0x04034B50 || view.getUint16(6, true) !== entry.flags ||
      view.getUint16(8, true) !== entry.method || nameLength > 4096 || dataOffset + entry.compressed > entry.nextOffset) {
      throw new Error('EPUB ZIP 资源头损坏');
    }
    const nameBytes: Uint8Array = await this.readAt(entry.offset + 30, nameLength);
    if (util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(nameBytes) !== entry.name ||
      ((entry.flags & 8) === 0 && (view.getUint32(14, true) !== entry.crc ||
        view.getUint32(18, true) !== entry.compressed || view.getUint32(22, true) !== entry.expanded))) {
      throw new Error('EPUB ZIP 资源信息不一致');
    }
    const source: Uint8Array = await this.readAt(dataOffset, entry.compressed);
    const output: Uint8Array = entry.method === 0 ? source : await this.inflate(source, entry.expanded);
    if (output.length !== entry.expanded || epubCrc32(output) !== entry.crc) {
      throw new Error('EPUB 资源校验失败，请重新下载');
    }
    return output;
  }

  async verify(): Promise<void> {
    const stat = await fs.stat(this.fd);
    if (stat.size !== this.size || stat.mtime !== this.modified) {
      throw new Error('EPUB 在导入期间发生变化，请重试');
    }
  }

  private async inflate(source: Uint8Array, expanded: number): Promise<Uint8Array> {
    const zip: zlib.Zip = await zlib.createZip();
    // One extra byte makes a forged small uncompressed size fail without allocating unbounded output.
    const output: ArrayBuffer = new ArrayBuffer(expanded + 1);
    const stream: zlib.ZStream = {
      nextIn: source.buffer, availableIn: source.length, nextOut: output, availableOut: expanded + 1
    };
    let initialized: boolean = false;
    try {
      if (await zip.inflateInit2(stream, -15) !== zlib.ReturnStatus.OK) {
        throw new Error('inflate init');
      }
      initialized = true;
      const status: zlib.ReturnStatus = await zip.inflate(stream, zlib.CompressFlushMode.FINISH);
      const result: zlib.ZStream = await zip.getZStream();
      if (status !== zlib.ReturnStatus.STREAM_END || result.totalOut !== expanded || result.totalIn !== source.length) {
        throw new Error('inflate bounds');
      }
      return new Uint8Array(output, 0, expanded);
    } catch (e) {
      throw new Error('EPUB 压缩正文损坏或超过声明大小');
    } finally {
      if (initialized) {
        await zip.inflateEnd({});
      }
    }
  }

  private async readAt(position: number, length: number): Promise<Uint8Array> {
    if (!Number.isSafeInteger(position) || !Number.isSafeInteger(length) || position < 0 || length < 0 ||
      position + length > this.size) {
      throw new Error('EPUB ZIP 读取位置越界');
    }
    const bytes: Uint8Array = new Uint8Array(length);
    fs.lseek(this.fd, position);
    let count: number = 0;
    while (count < length) {
      const size: number = Math.min(128 * 1024, length - count);
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      const read: number = await fs.read(this.fd, buffer, { length: size });
      if (read <= 0 || read > size) {
        throw new Error('EPUB ZIP 文件读取不完整');
      }
      bytes.set(new Uint8Array(buffer, 0, read), count);
      count += read;
    }
    return bytes;
  }
}
