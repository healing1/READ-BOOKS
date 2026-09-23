import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { EpubArchive, safeEpubPath } from './EpubArchive';
import { EpubDocument, EpubNavEntry } from './EpubDocument';
import { EpubFonts } from './EpubFonts';
import { ReadingFonts } from './ReadingFonts';
import { EpubResourceCache } from './EpubResourceCache';

export const EPUB_ORIGIN: string = 'https://readbooks.invalid/';
const POLICY: string = "default-src 'none'; script-src 'none'; style-src 'self' 'unsafe-inline'; " +
  "img-src 'self' data:; font-src 'self' data:; media-src 'none'; connect-src 'none'; " +
  "frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";

export function epubUrl(path: string, fragment: string = '', origin: string = EPUB_ORIGIN): string {
  return origin + path.split('/').map((part: string) => encodeURIComponent(part)).join('/') + (fragment ? '#' + fragment : '');
}

export function epubRequestPath(url: string, origin: string = EPUB_ORIGIN): string {
  if (!url.startsWith(origin)) { throw new Error('外部资源已阻止'); }
  return safeEpubPath(decodeURIComponent(url.substring(origin.length).split('#')[0].split('?')[0]));
}

export class EpubResources {
  private static sequence: number = 0;
  origin: string = EPUB_ORIGIN;
  private file: fs.File | null = null;
  private archive: EpubArchive | null = null;
  private queue: Promise<void> = Promise.resolve();
  private closed: boolean = false;
  private fonts: EpubFonts = new EpubFonts();
  private mediaTypes: Map<string, string> = new Map<string, string>();
  private cache: EpubResourceCache = new EpubResourceCache();
  private chapterCache: EpubResourceCache = new EpubResourceCache(16 * 1024 * 1024, 50);
  private prefetchPaths: string[] = [];
  private prefetchEpoch: number = 0;
  private prefetchTimer: number = -1;
  private foregroundRequests: number = 0;
  private prefetchPauseUntil: number = 0;
  mainPath: string = '';
  fontPath: string = '';
  backgroundPath: string = '';
  navigation: EpubNavEntry[] = [];
  onFailure: (message: string) => void = () => {};
  onPrefetchReady: (count: number, bytes: number) => void = () => {};
  loadBuiltinFont: (resource: string) => Promise<Uint8Array> = async () => { throw new Error('内置字体尚未就绪'); };

  async open(path: string): Promise<void> {
    // Immutable assets may be reused by ArkWeb, but never across two open books with identical ZIP paths.
    this.origin = 'https://book-' + Date.now() + '-' + EpubResources.sequence++ + '.readbooks.invalid/';
    this.file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(this.file.fd);
      this.archive = new EpubArchive(this.file.fd, stat.size, stat.mtime);
      await this.archive.initialize();
      const opf = EpubDocument.containerPath(await this.archive.readText('META-INF/container.xml', 1024 * 1024));
      const metadata = EpubDocument.package(await this.archive.readText(opf, 1024 * 1024), opf);
      this.fonts = await EpubFonts.inspect(this.archive, metadata);
      this.mediaTypes = metadata.mediaTypes;
      if (metadata.navigationPath) {
        try { this.navigation = EpubDocument.navigationEntries(await this.archive.readText(metadata.navigationPath, 1024 * 1024), metadata.navigationPath); }
        catch (_) {}
      }
    } catch (e) { await this.close(); throw e instanceof Error ? e : new Error('无法读取原版 EPUB'); }
  }

  has(path: string): boolean { return this.archive?.has(path) ?? false; }

  /** Yield background work during input and its short settle, without discarding cached chapters. */
  deferPrefetch(): void { this.prefetchPauseUntil = Date.now() + 380; }
  get prefetchDeferred(): boolean { return Date.now() < this.prefetchPauseUntil; }

  async close(): Promise<void> {
    this.closed = true;
    this.prefetchEpoch++; this.prefetchPaths = []; clearTimeout(this.prefetchTimer);
    await this.queue;
    if (this.file !== null) { await fs.close(this.file); this.file = null; }
    this.archive = null;
    this.cache.clear();
    this.chapterCache.clear();
  }

  /** Rolling current..current+49 window. One small document per idle slice, with foreground priority. */
  prefetchWindow(paths: string[]): void {
    this.prefetchPaths = paths.slice(0, 50);
    this.chapterCache.retain(this.prefetchPaths);
    const epoch: number = ++this.prefetchEpoch;
    clearTimeout(this.prefetchTimer);
    this.schedulePrefetch(epoch);
  }

  private schedulePrefetch(epoch: number): void {
    if (this.closed || epoch !== this.prefetchEpoch) { return; }
    if (!this.prefetchPaths.length) { this.onPrefetchReady(this.chapterCache.count(), this.chapterCache.sizeBytes()); return; }
    this.prefetchTimer = setTimeout(async () => {
      if (this.closed || epoch !== this.prefetchEpoch) { return; }
      if (this.foregroundRequests === 0 && !this.prefetchDeferred) {
        const path: string = this.prefetchPaths.shift()!;
        this.prefetch(path);
        await this.queue;
      }
      this.schedulePrefetch(epoch);
    }, 24);
  }

  /** Tiny neighbouring chapter documents only; never inflate a whole book into memory. */
  prefetch(path: string): void {
    if (this.closed || !this.archive?.has(path) || this.chapterCache.get(path) !== undefined) { return; }
    this.queue = this.queue.catch(() => {}).then(async () => {
      if (this.closed || this.archive === null || this.chapterCache.get(path) !== undefined) { return; }
      try {
        const bytes = await this.archive.readEntry(path, 512 * 1024);
        if (!this.closed) { this.chapterCache.put(path, this.fonts.decode(path, bytes)); }
      } catch (_) { /* Prefetch cannot fail foreground navigation or weaken its normal validation. */ }
    });
  }

  response(url: string, documentPath: string = this.mainPath): WebResourceResponse {
    const response = new WebResourceResponse();
    response.setResponseIsReady(false);
    this.foregroundRequests++;
    // Shared descriptor seeks must never overlap. Also bounds concurrent inflated allocations to one entry.
    this.queue = this.queue.catch(() => {}).then(async () => {
      let optionalFont: boolean = false;
      try {
        if (this.closed || this.archive === null) { throw new Error('图书已关闭'); }
        const path = epubRequestPath(url, this.origin);
        let mime: string = this.mime(path);
        let bytes: Uint8Array;
        const builtin: string = ReadingFonts.resource(path);
        if (builtin) {
          bytes = this.cache.get('builtin:' + builtin) ?? await this.loadBuiltinFont(builtin);
          this.cache.put('builtin:' + builtin, bytes);
        } else if (path === '__reader_font__' || path === '__reader_background__') {
          const asset = path === '__reader_font__' ? this.fontPath : this.backgroundPath;
          if (!asset) { throw new Error('尚未选择素材'); }
          // Imported assets have immutable, unique paths, so replacing a font never reuses stale bytes.
          bytes = this.cache.get('asset:' + asset) ?? await this.asset(asset);
          this.cache.put('asset:' + asset, bytes);
          mime = path === '__reader_font__' ? 'font/ttf' : 'image/png';
          if (path === '__reader_font__' && bytes.length >= 4 && new DataView(bytes.buffer).getUint32(0) === 0x4F54544F) { mime = 'font/otf'; }
        } else {
          if (!this.archive.has(path)) {
            // CSS commonly lists fonts absent from an EPUB and then falls back to local faces.
            optionalFont = mime.startsWith('font/') && !this.mediaTypes.has(path);
            throw new Error('原书未包含资源：' + path.substring(path.lastIndexOf('/') + 1));
          }
          const chapter: boolean = mime === 'text/html' || (mime === 'image/svg+xml' && documentPath === path);
          const storage: EpubResourceCache = chapter ? this.chapterCache : this.cache;
          bytes = storage.get(path) ?? this.fonts.decode(path, await this.archive.readEntry(path, 64 * 1024 * 1024));
          storage.put(path, bytes);
        }
        response.setResponseCode(200);
        response.setReasonMessage('OK');
        response.setResponseEncoding('utf-8');
        response.setResponseHeader([{ headerKey: 'Content-Security-Policy', headerValue: POLICY },
          { headerKey: 'Cache-Control', headerValue: mime === 'text/html' || path === documentPath || path === '__reader_background__' ?
            'no-store' : 'private, max-age=3600' },
          { headerKey: 'X-Content-Type-Options', headerValue: 'nosniff' }]);
        if (mime === 'text/html' || (mime === 'image/svg+xml' && documentPath === path)) {
          let html = EpubArchive.decodeText(bytes);
          if (mime === 'image/svg+xml') { html = '<html><head></head><body>' + html.replace(/<\?xml[^>]*>/gi, '') + '</body></html>'; }
          // Response CSP applies before parsing; this first meta also protects engines with incomplete header interception.
          const guard: string = '<meta http-equiv="Content-Security-Policy" content="' + POLICY + '">' +
            '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">' +
            '<style id="readbooks-first-paint">html:root{opacity:0!important}</style>';
          html = html.replace(/<\?xml[^>]*>/gi, '');
          html = html.replace(/(<meta\b[^>]*\bname\s*=\s*["'])viewport(["'])/gi, '$1readbooks-publisher-viewport$2');
          html = /<head\b[^>]*>/i.test(html) ? html.replace(/<head\b[^>]*>/i, '<head>' + guard) : guard + html;
          response.setResponseData(html);
          mime = 'text/html';
        } else {
          response.setResponseData((bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength ?
            bytes.buffer : bytes.slice().buffer) as ArrayBuffer);
        }
        response.setResponseMimeType(mime);
      } catch (e) {
        response.setResponseCode(404); response.setReasonMessage('Not Found');
        response.setResponseMimeType('text/plain'); response.setResponseData('');
        if (!this.closed && !optionalFont && url.startsWith(this.origin) && !url.endsWith('favicon.ico')) {
          this.onFailure(e instanceof Error ? e.message : '书内资源无法加载');
        }
      } finally { this.foregroundRequests--; response.setResponseIsReady(true); }
    });
    return response;
  }

  private async asset(path: string): Promise<Uint8Array> {
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const size = (await fs.stat(file.fd)).size;
      if (size <= 0 || size > 64 * 1024 * 1024) { throw new Error('阅读素材大小无效'); }
      const bytes = new Uint8Array(size);
      let offset: number = 0;
      while (offset < size) {
        const chunk = new ArrayBuffer(Math.min(128 * 1024, size - offset));
        const count = await fs.read(file.fd, chunk);
        if (count <= 0) { throw new Error('阅读素材不完整'); }
        bytes.set(new Uint8Array(chunk, 0, count), offset); offset += count;
      }
      return bytes;
    } finally { await fs.close(file); }
  }

  private mime(path: string): string {
    const declared = this.mediaTypes.get(path);
    if (declared === 'application/xhtml+xml') { return 'text/html'; }
    if (declared && /^(image\/|font\/|text\/css|text\/html)/.test(declared)) { return declared; }
    const ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
    const types: Record<string, string> = { 'xhtml': 'text/html', 'html': 'text/html', 'htm': 'text/html',
      'css': 'text/css', 'svg': 'image/svg+xml', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'avif': 'image/avif', 'ttf': 'font/ttf', 'otf': 'font/otf',
      'woff': 'font/woff', 'woff2': 'font/woff2' };
    return types[ext] ?? 'application/octet-stream';
  }
}
