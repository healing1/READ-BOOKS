import { util } from '@kit.ArkTS';

/** 编码检测 —— docs/DESIGN.md §5.2：BOM → 严格 UTF-8 → GB18030 兜底 */
export class EncodingDetector {
  static detectBom(bytes: Uint8Array, totalBytes: number): string {
    if (bytes.length >= 4 &&
      ((bytes[0] === 0xFF && bytes[1] === 0xFE && bytes[2] === 0 && bytes[3] === 0) ||
      (bytes[0] === 0 && bytes[1] === 0 && bytes[2] === 0xFE && bytes[3] === 0xFF))) {
      throw new Error('暂不支持 UTF-32，请先将 TXT 转换为 UTF-8');
    }
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      return 'utf-8';
    }
    if (bytes.length >= 2 && ((bytes[0] === 0xFF && bytes[1] === 0xFE) ||
      (bytes[0] === 0xFE && bytes[1] === 0xFF))) {
      if (totalBytes % 2 !== 0) {
        throw new Error('UTF-16 文件内容不完整');
      }
      return bytes[0] === 0xFF ? 'utf-16le' : 'utf-16be';
    }
    return '';
  }

  static detect(bytes: Uint8Array): string {
    if (bytes.length >= 4 &&
      ((bytes[0] === 0xFF && bytes[1] === 0xFE && bytes[2] === 0 && bytes[3] === 0) ||
      (bytes[0] === 0 && bytes[1] === 0 && bytes[2] === 0xFE && bytes[3] === 0xFF))) {
      throw new Error('暂不支持 UTF-32，请先将 TXT 转换为 UTF-8');
    }
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      if (!EncodingDetector.isValidUtf8(bytes)) {
        throw new Error('UTF-8 文件内容损坏');
      }
      return 'utf-8';
    }
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      EncodingDetector.ensureCompleteUtf16(bytes);
      return 'utf-16le';
    }
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      EncodingDetector.ensureCompleteUtf16(bytes);
      return 'utf-16be';
    }
    return EncodingDetector.isValidUtf8(bytes) ? 'utf-8' : 'gb18030';
  }

  static decode(bytes: Uint8Array, encoding: string): string {
    const dec = util.TextDecoder.create(encoding, { fatal: true });
    let s: string = dec.decodeToString(bytes, { stream: false });
    if (s.length > 0 && s.charCodeAt(0) === 0xFEFF) {
      s = s.substring(1);
    }
    return s;
  }

  /** Reject renamed binary files instead of importing control codes as a book. */
  static validateText(text: string): void {
    const validator: StreamingTextValidator = new StreamingTextValidator();
    validator.push(text);
    validator.finish();
  }

  private static isValidUtf8(bytes: Uint8Array): boolean {
    let i: number = 0;
    while (i < bytes.length) {
      const first: number = bytes[i];
      if (first <= 0x7F) {
        i++;
        continue;
      }

      if (first >= 0xC2 && first <= 0xDF) {
        if (!EncodingDetector.isContinuation(bytes, i + 1)) {
          return false;
        }
        i += 2;
        continue;
      }

      if (first >= 0xE0 && first <= 0xEF) {
        if (i + 2 >= bytes.length) {
          return false;
        }
        const second: number = bytes[i + 1];
        const secondValid: boolean = first === 0xE0 ? second >= 0xA0 && second <= 0xBF :
          first === 0xED ? second >= 0x80 && second <= 0x9F : second >= 0x80 && second <= 0xBF;
        if (!secondValid || !EncodingDetector.isContinuation(bytes, i + 2)) {
          return false;
        }
        i += 3;
        continue;
      }

      if (first >= 0xF0 && first <= 0xF4) {
        if (i + 3 >= bytes.length) {
          return false;
        }
        const second: number = bytes[i + 1];
        const secondValid: boolean = first === 0xF0 ? second >= 0x90 && second <= 0xBF :
          first === 0xF4 ? second >= 0x80 && second <= 0x8F : second >= 0x80 && second <= 0xBF;
        if (!secondValid || !EncodingDetector.isContinuation(bytes, i + 2) ||
          !EncodingDetector.isContinuation(bytes, i + 3)) {
          return false;
        }
        i += 4;
        continue;
      }
      return false;
    }
    return true;
  }

  private static isContinuation(bytes: Uint8Array, index: number): boolean {
    return index < bytes.length && bytes[index] >= 0x80 && bytes[index] <= 0xBF;
  }

  private static ensureCompleteUtf16(bytes: Uint8Array): void {
    if (bytes.length % 2 !== 0) {
      throw new Error('UTF-16 文件内容不完整');
    }
  }
}

export class StreamingTextValidator {
  private length: number = 0;
  private controls: number = 0;
  private readable: boolean = false;

  push(text: string): void {
    this.length += text.length;
    this.readable = this.readable || /\S/.test(text);
    for (let i: number = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      if (code === 0) {
        throw new Error('文件不是有效 TXT 文本，请检查文件格式和编码');
      }
      if ((code < 0x20 && code !== 0x09 && code !== 0x0A && code !== 0x0C && code !== 0x0D) || code === 0x7F) {
        this.controls++;
      }
    }
  }

  finish(): void {
    if (!this.readable) {
      throw new Error('TXT 文件没有可阅读内容');
    }
    if (this.controls > Math.max(2, this.length / 1000)) {
      throw new Error('文件包含过多非文本内容，请导入纯文本 TXT');
    }
  }
}

/** Carries only CR and BOM state across decoder chunks. */
export class StreamingTextNormalizer {
  private first: boolean = true;
  private trailingCr: boolean = false;

  push(chunk: string, final: boolean = false): string {
    let text: string = chunk;
    if (this.first && text.length > 0) {
      if (text.charCodeAt(0) === 0xFEFF) {
        text = text.substring(1);
      }
      this.first = false;
    }
    let prefix: string = '';
    if (this.trailingCr && (text.length > 0 || final)) {
      prefix = '\n';
      if (text.startsWith('\n')) {
        text = text.substring(1);
      }
      this.trailingCr = false;
    }
    if (!final && text.endsWith('\r')) {
      text = text.substring(0, text.length - 1);
      this.trailingCr = true;
    }
    return prefix + text.replace(/\r\n?/g, '\n');
  }
}

/** Strict UTF-8 detection without allocating decoded strings or retaining the source. */
export class StreamingUtf8Validator {
  private remaining: number = 0;
  private lower: number = 0x80;
  private upper: number = 0xBF;
  private valid: boolean = true;

  push(bytes: Uint8Array): void {
    if (!this.valid) {
      return;
    }
    for (let i: number = 0; i < bytes.length; i++) {
      const byte: number = bytes[i];
      if (this.remaining > 0) {
        if (byte < this.lower || byte > this.upper) {
          this.valid = false;
          return;
        }
        this.remaining--;
        this.lower = 0x80;
        this.upper = 0xBF;
      } else if (byte >= 0xC2 && byte <= 0xDF) {
        this.remaining = 1;
      } else if (byte >= 0xE0 && byte <= 0xEF) {
        this.remaining = 2;
        this.lower = byte === 0xE0 ? 0xA0 : 0x80;
        this.upper = byte === 0xED ? 0x9F : 0xBF;
      } else if (byte >= 0xF0 && byte <= 0xF4) {
        this.remaining = 3;
        this.lower = byte === 0xF0 ? 0x90 : 0x80;
        this.upper = byte === 0xF4 ? 0x8F : 0xBF;
      } else if (byte >= 0x80) {
        this.valid = false;
        return;
      }
    }
  }

  finish(): boolean {
    return this.valid && this.remaining === 0;
  }
}
