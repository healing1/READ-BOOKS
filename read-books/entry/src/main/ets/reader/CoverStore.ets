import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { Db } from '../data/Db';
import { BookRepo } from '../data/BookRepo';
import { ImportActivity } from './ImportActivity';

/** Small, decoded, app-owned thumbnails. Never writes to a picker URI or an original book. */
export class CoverStore {
  static async normalize(bytes: Uint8Array, background: boolean = false): Promise<Uint8Array> {
    if (bytes.length === 0 || bytes.length > 16 * 1024 * 1024) { throw new Error('封面图片不能超过 16 MiB'); }
    const source = image.createImageSource(bytes.slice().buffer as ArrayBuffer);
    try {
      const info = await source.getImageInfo();
      const width: number = info.size.width;
      const height: number = info.size.height;
      if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0 ||
        width > 8192 || height > 8192 || width * height > 16000000) {
        throw new Error('封面分辨率过大，请选择 1600 万像素以内的图片');
      }
      const scale: number = background ? Math.min(1, 2800 / width, 2800 / height) : Math.min(1, 640 / width, 960 / height);
      const pixels = await source.createPixelMap({ desiredSize: {
        width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) } });
      try {
        const packer = image.createImagePacker();
        try { return new Uint8Array(await packer.packing(pixels, { format: 'image/png', quality: 95 })); }
        finally { await packer.release(); }
      } finally { await pixels.release(); }
    } finally { await source.release(); }
  }

  static async readImage(uri: string, background: boolean = false): Promise<Uint8Array> {
    const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const before = await fs.stat(file.fd);
      if (!Number.isSafeInteger(before.size) || before.size <= 0 || before.size > 16 * 1024 * 1024) {
        throw new Error('请选择 16 MiB 以内的 PNG 或 JPEG 封面图片');
      }
      const buffer: ArrayBuffer = new ArrayBuffer(before.size);
      let offset: number = 0;
      while (offset < before.size) {
        const chunk: ArrayBuffer = new ArrayBuffer(Math.min(128 * 1024, before.size - offset));
        const count: number = await fs.read(file.fd, chunk);
        if (count <= 0 || count > chunk.byteLength) { throw new Error('封面图片读取不完整'); }
        new Uint8Array(buffer).set(new Uint8Array(chunk, 0, count), offset);
        offset += count;
      }
      const after = await fs.stat(file.fd);
      if (after.size !== before.size || after.mtime !== before.mtime) { throw new Error('图片在读取时发生变化，请重试'); }
      return await CoverStore.normalize(new Uint8Array(buffer), background);
    } finally { await fs.close(file); }
  }

  /** Caller must finish/discard the reservation after publishing the database reference. */
  static async stage(context: common.UIAbilityContext, bytes: Uint8Array): Promise<string> {
    if (bytes.length === 0 || bytes.length > 4 * 1024 * 1024) { throw new Error('封面缩略图大小无效'); }
    const directory: string = Db.booksDirectory(context);
    if (!fs.accessSync(directory)) { fs.mkdirSync(directory); }
    const path: string = ImportActivity.reserveCover(directory);
    try {
      const file = await fs.open(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        let offset: number = 0;
        while (offset < bytes.length) {
          const chunk: Uint8Array = bytes.slice(offset, Math.min(bytes.length, offset + 128 * 1024));
          const count: number = await fs.write(file.fd, chunk.buffer);
          if (count <= 0 || count > chunk.length) { throw new Error('写入封面失败，请检查可用空间'); }
          offset += count;
        }
        await fs.fsync(file.fd);
      } finally { await fs.close(file); }
      await fs.rename(path + '.tmp', path);
      return path;
    } catch (e) {
      CoverStore.finish(path);
      await CoverStore.removeUnused(context, path + '.tmp');
      await CoverStore.removeUnused(context, path);
      throw e instanceof Error ? e : new Error('保存封面失败');
    }
  }

  static finish(path: string): void {
    ImportActivity.remove(path);
    ImportActivity.remove(path + '.tmp');
  }

  static async removeUnused(context: common.UIAbilityContext, path: string): Promise<void> {
    const prefix: string = Db.booksDirectory(context) + '/';
    if (!path.startsWith(prefix) || !/^book_[0-9]+_[0-9]+_cover\.(png|jpg|jpeg)(\.tmp)?$/.test(path.substring(prefix.length))) {
      return;
    }
    try {
      if (!ImportActivity.has(path) && !await BookRepo.hasLiveFile(path) && fs.accessSync(path)) { await fs.unlink(path); }
    } catch (e) { /* Startup recovery retries; never delete when the database cannot confirm ownership. */ }
  }

  static async replace(context: common.UIAbilityContext, id: number, expected: string, bytes: Uint8Array): Promise<void> {
    const path: string = await CoverStore.stage(context, bytes);
    try {
      await BookRepo.replaceCover(id, path, expected);
    } finally {
      CoverStore.finish(path);
      await CoverStore.removeUnused(context, path);
    }
    await CoverStore.removeUnused(context, expected);
  }
}
