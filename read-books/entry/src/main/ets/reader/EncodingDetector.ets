import { util } from '@kit.ArkTS';

/** 编码检测 —— docs/DESIGN.md §5.2：BOM → 严格 UTF-8 → GB18030 兜底 */
export class EncodingDetector {
  static detect(bytes: Uint8Array): string {
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      return 'utf-8';
    }
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      return 'utf-16le';
    }
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      return 'utf-16be';
    }
    // 取样严格 UTF-8 校验；回退多字节边界，避免样本截断误判
    let end: number = Math.min(bytes.length, 65536);
    while (end > 0 && end > 65536 - 4 && (bytes[end - 1] & 0xC0) === 0x80) {
      end--;
    }
    const sample: Uint8Array = bytes.subarray(0, end);
    try {
      const strict = util.TextDecoder.create('utf-8', { fatal: true });
      strict.decodeWithStream(sample, { stream: false });
      return 'utf-8';
    } catch (e) {
      return 'gb18030';
    }
  }

  static decode(bytes: Uint8Array, encoding: string): string {
    const dec = util.TextDecoder.create(encoding);
    let s: string = dec.decodeWithStream(bytes, { stream: false });
    if (s.length > 0 && s.charCodeAt(0) === 0xFEFF) {
      s = s.substring(1);
    }
    return s;
  }
}
