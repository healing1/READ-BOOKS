import { image } from '@kit.ImageKit';
import { Book } from '../model/Models';
import { CoverColors } from '../theme/CoverColors';

export class CoverAppearance {
  ratio: number; tone: string;
  constructor(ratio: number, tone: string) { this.ratio = ratio; this.tone = tone; }
}
export class CoverVisual {
  private static cache: Map<string, Promise<CoverAppearance>> = new Map<string, Promise<CoverAppearance>>();
  static read(book: Book): Promise<CoverAppearance> {
    if (!book.coverPath) { return Promise.resolve(new CoverAppearance(0.66, book.coverColor)); }
    const cached = CoverVisual.cache.get(book.coverPath);
    if (cached !== undefined) { return cached; }
    if (CoverVisual.cache.size > 64) { CoverVisual.cache.clear(); }
    const task = CoverVisual.decode(book.coverPath, book.coverColor);
    CoverVisual.cache.set(book.coverPath, task);
    return task;
  }
  private static async decode(path: string, fallback: string): Promise<CoverAppearance> {
    try {
      const source = image.createImageSource(path);
      try {
        const info = await source.getImageInfo();
        const ratio: number = info.size.width / Math.max(1, info.size.height);
        const pixels = await source.createPixelMap({ desiredSize: { width: 32, height: 32 }, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
        try {
          const buffer: ArrayBuffer = new ArrayBuffer(32 * 32 * 4);
          await pixels.readPixelsToBuffer(buffer);
          return new CoverAppearance(ratio, CoverColors.dominant(new Uint8Array(buffer), fallback));
        } finally { await pixels.release(); }
      } finally { await source.release(); }
    } catch (_) { return new CoverAppearance(0.66, fallback); }
  }
}
