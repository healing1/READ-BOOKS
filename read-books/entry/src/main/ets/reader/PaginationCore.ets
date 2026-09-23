import { LineInfo, Page } from '../model/Models';

/** Canvas 只在 UI 线程测量；后台分页仅消费测好的字宽。 */
export interface Measurer {
  measure(ch: string): number;
  prepare?(): void;
}

export interface LayoutConstraints {
  widthPx: number;
  heightPx: number;
  padLeftPx: number;
  padRightPx: number;
  padTopPx: number;
  padBottomPx: number;
  fontSizePx: number;
  lineHeightRatio: number;
}

/** 无 ArkUI 依赖，UI / TaskPool 两条路径共用同一排版实现。 */
export class PaginationCore {
  static glyphAt(text: string, offset: number): string {
    const first: number = text.charCodeAt(offset);
    if (first >= 0xD800 && first <= 0xDBFF && offset + 1 < text.length) {
      const next: number = text.charCodeAt(offset + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        return text.substring(offset, offset + 2);
      }
    }
    return text.charAt(offset);
  }

  private static previousOffset(text: string, offset: number): number {
    let previous: number = offset - 1;
    if (previous > 0) {
      const code: number = text.charCodeAt(previous);
      const lead: number = text.charCodeAt(previous - 1);
      if (code >= 0xDC00 && code <= 0xDFFF && lead >= 0xD800 && lead <= 0xDBFF) {
        previous--;
      }
    }
    return Math.max(0, previous);
  }

  private static isWord(ch: string): boolean {
    return /^[A-Za-z0-9_'’\-]$/.test(ch);
  }

  private static isClosing(ch: string): boolean {
    return ch.length > 0 && '，。！？：；、）》」』】〕〉”’…,.!?;:%)]}'.indexOf(ch) >= 0;
  }

  private static isOpening(ch: string): boolean {
    return ch.length > 0 && '（《「『【〔〈“‘([{'.indexOf(ch) >= 0;
  }

  /** 不拆普通英文词；超长单词仍可换行。中日韩禁则不以溢出正文区域为代价。 */
  private static lineEnd(para: string, start: number, width: number, measurer: Measurer): number {
    let end: number = start;
    let used: number = 0;
    while (end < para.length) {
      const glyph: string = PaginationCore.glyphAt(para, end);
      const measured: number = measurer.measure(glyph);
      const glyphWidth: number = Number.isFinite(measured) ? Math.max(0, measured) : 0;
      if (used + glyphWidth > width && end > start) {
        break;
      }
      used += glyphWidth;
      end += glyph.length;
    }
    if (end >= para.length) {
      return end;
    }

    let adjusted: number = end;
    const previous: number = PaginationCore.previousOffset(para, adjusted);
    if (PaginationCore.isWord(PaginationCore.glyphAt(para, previous)) &&
      PaginationCore.isWord(PaginationCore.glyphAt(para, adjusted))) {
      let wordStart: number = adjusted;
      while (wordStart > start) {
        const before: number = PaginationCore.previousOffset(para, wordStart);
        if (!PaginationCore.isWord(PaginationCore.glyphAt(para, before))) {
          break;
        }
        wordStart = before;
      }
      if (wordStart > start) {
        adjusted = wordStart;
      }
    }

    if (PaginationCore.isClosing(PaginationCore.glyphAt(para, adjusted))) {
      let before: number = PaginationCore.previousOffset(para, adjusted);
      while (before > start && PaginationCore.isClosing(PaginationCore.glyphAt(para, before))) {
        before = PaginationCore.previousOffset(para, before);
      }
      if (PaginationCore.isWord(PaginationCore.glyphAt(para, before))) {
        let wordStart: number = before;
        while (wordStart > start) {
          const previousWord: number = PaginationCore.previousOffset(para, wordStart);
          if (!PaginationCore.isWord(PaginationCore.glyphAt(para, previousWord))) {
            break;
          }
          wordStart = previousWord;
        }
        if (wordStart > start) {
          before = wordStart;
        }
      }
      if (before > start) {
        adjusted = before;
      }
    }
    while (adjusted > start) {
      const before: number = PaginationCore.previousOffset(para, adjusted);
      if (!PaginationCore.isOpening(PaginationCore.glyphAt(para, before)) || before <= start) {
        break;
      }
      adjusted = before;
    }
    return adjusted > start ? adjusted : end;
  }

  static paginate(body: string, chapterIdx: number, startOffset: number,
    lc: LayoutConstraints, measurer: Measurer): Page[] {
    const pages: Page[] = [];
    const maxW: number = lc.widthPx - lc.padLeftPx - lc.padRightPx;
    const contentBottom: number = lc.heightPx - lc.padBottomPx;
    const lineH: number = lc.fontSizePx * lc.lineHeightRatio;
    if (!Number.isFinite(maxW) || !Number.isFinite(lineH) || !Number.isFinite(contentBottom) ||
      maxW <= 0 || lc.fontSizePx <= 0 || lineH <= 0 || contentBottom - lc.padTopPx < lineH) {
      return pages;
    }
    const paraGap: number = lineH * 0.4;
    const blankGap: number = lineH * 0.8;
    const indentW: number = measurer.measure('　') * 2;
    // 极窄分屏不强塞 2em 缩进，以免第一字被推出屏幕。
    const indent: boolean = maxW >= indentW + lc.fontSizePx;
    let lines: LineInfo[] = [];
    let y: number = lc.padTopPx;
    let pageStart: number = startOffset;
    let pos: number = 0;
    while (pos < body.length) {
      const nl: number = body.indexOf('\n', pos);
      const paraEnd: number = nl === -1 ? body.length : nl;
      const para: string = body.substring(pos, paraEnd);
      if (para.length === 0) {
        y += blankGap;
      } else {
        let i: number = 0;
        let firstLine: boolean = true;
        while (i < para.length) {
          const withIndent: boolean = firstLine && indent;
          const end: number = PaginationCore.lineEnd(para, i, maxW - (withIndent ? indentW : 0), measurer);
          const absStart: number = startOffset + pos + i;
          if (y + lineH > contentBottom) {
            if (lines.length > 0) {
              pages.push(new Page(chapterIdx, pageStart, absStart, lines));
              pageStart = absStart;
            }
            lines = [];
            y = lc.padTopPx;
          }
          lines.push(new LineInfo((withIndent ? '　　' : '') + para.substring(i, end), y,
            absStart, startOffset + pos + end));
          y += lineH;
          i = end;
          firstLine = false;
        }
        y += paraGap;
      }
      if (nl === -1) {
        break;
      }
      pos = nl + 1;
    }
    // 页范围连续包含换行/空白，锚点始终有明确归属；全空白章节也保留一个有效页。
    pages.push(new Page(chapterIdx, pageStart, startOffset + body.length, lines));
    return pages;
  }
}

export class WidthTableMeasurer implements Measurer {
  private widths: Map<string, number>;
  private fallback: number;

  constructor(widths: Map<string, number>, fallback: number) {
    this.widths = widths;
    this.fallback = fallback;
  }

  measure(ch: string): number {
    const width: number | undefined = this.widths.get(ch);
    return width === undefined ? this.fallback : width;
  }
}
