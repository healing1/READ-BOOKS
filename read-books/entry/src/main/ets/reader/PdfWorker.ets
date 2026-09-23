import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';

/** Keep the worker module isolated from UI/database imports. */
@Concurrent
export function inspectPdfDocument(path: string): number {
  const document = new pdfService.PdfDocument();
  try {
    if (document.isEncrypted(path)) {
      throw new Error('暂不支持加密 PDF，请先提供无密码且未加密的副本');
    }
    const result: pdfService.ParseResult = document.loadDocument(path);
    if (result === pdfService.ParseResult.PARSE_ERROR_PASSWORD || result === pdfService.ParseResult.PARSE_ERROR_CERT) {
      throw new Error('暂不支持需要密码或证书的 PDF，请先提供未加密的副本');
    }
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) { throw new Error('PDF 文件损坏或格式无效，无法打开'); }
    const pages: number = document.getPageCount();
    if (!Number.isSafeInteger(pages) || pages <= 0) { throw new Error('PDF 没有可阅读的页面'); }
    return pages;
  } finally { document.releaseDocument(); }
}

/** Render only page zero into a bounded bitmap; never allocate a full-resolution page on the UI thread. */
@Concurrent
export async function renderPdfCover(path: string): Promise<ArrayBuffer> {
  const document = new pdfService.PdfDocument();
  try {
    if (document.isEncrypted(path) || document.loadDocument(path) !== pdfService.ParseResult.PARSE_SUCCESS ||
      document.getPageCount() < 1) { throw new Error('无法生成 PDF 封面'); }
    const page = document.getPage(0);
    try {
      const width: number = page.getWidth();
      const height: number = page.getHeight();
      if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0 || width > 14400 || height > 14400) {
        throw new Error('PDF 首页尺寸无效或过大');
      }
      const scale: number = Math.min(640 / width, 960 / height);
      const matrix = new pdfService.PdfMatrix();
      matrix.x = 0;
      matrix.y = 0;
      matrix.width = width;
      matrix.height = height;
      matrix.rotate = 0;
      const pixels = page.getAreaPixelMap(matrix, Math.max(1, Math.round(width * scale)),
        Math.max(1, Math.round(height * scale)), false, false);
      try {
        const packer = image.createImagePacker();
        try { return await packer.packing(pixels, { format: 'image/png', quality: 95 }); }
        finally { await packer.release(); }
      } finally { await pixels.release(); }
    } finally { page.release(); }
  } finally { document.releaseDocument(); }
}
