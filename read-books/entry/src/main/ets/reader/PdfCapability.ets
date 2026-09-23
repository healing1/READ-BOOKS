import { pdfService } from '@kit.PDFKit';

export const PDF_UNAVAILABLE: string = '当前设备未提供华为 PDF Kit。此 x86 模拟器无法预览 PDF，请连接 HarmonyOS 真机验证。';

export function supportsNativePdf(): boolean {
  try { return typeof pdfService.PdfDocument === 'function'; }
  catch (e) { return false; }
}

export function requireNativePdf(): void {
  if (!supportsNativePdf()) { throw new Error(PDF_UNAVAILABLE); }
}
