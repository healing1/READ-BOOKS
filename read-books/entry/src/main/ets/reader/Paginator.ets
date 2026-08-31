import { Chapter, LineInfo, Page } from '../model/Models';

/** 文本测量器（UI 侧注入 Canvas 实现，引擎保持纯逻辑） —— docs/DESIGN.md §5.4 */
export interface Measurer {
  measure(ch: string): number;
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

/**
 * 分页器 —— docs/DESIGN.md §5.4
 * 贪心组行：字符宽度缓存 + 视口宽度断行；段首缩进 2em、段间距 0.4 行、空行 0.8 行
 * MVP 在 UI 线程按章惰性分页 + LRU 缓存；TaskPool 后台预分页为既定演进方向
 */
export class Paginator {
  static paginateChapter(text: string, chapter: Chapter, lc: LayoutConstraints, measurer: Measurer): Page[] {
    const pages: Page[] = [];
    const maxW: number = lc.widthPx - lc.padLeftPx - lc.padRightPx;
    if (maxW <= 0 || lc.fontSizePx <= 0) {
      return pages;
    }
    const contentBottom: number = lc.heightPx - lc.padBottomPx;
    const lineH: number = lc.fontSizePx * lc.lineHeightRatio;
    const paraGap: number = lineH * 0.4;
    const blankGap: number = lineH * 0.8;
    const indentStr: string = '　　';
    const indentW: number = measurer.measure('　') * 2;

    const body: string = text.substring(chapter.startOffset, chapter.endOffset);
    const total: number = body.length;
    let lines: LineInfo[] = [];
    let y: number = lc.padTopPx;
    let pageStart: number = -1;
    let pageEnd: number = -1;

    let pos: number = 0;
    while (pos < total) {
      const nl: number = body.indexOf('\n', pos);
      const paraEnd: number = nl === -1 ? total : nl;
      const para: string = body.substring(pos, paraEnd);
      if (para.length === 0) {
        y += blankGap;
      } else {
        let i: number = 0;
        let firstLine: boolean = true;
        while (i < para.length) {
          let w: number = firstLine ? indentW : 0;
          let j: number = i;
          while (j < para.length) {
            const cw: number = measurer.measure(para.charAt(j));
            if (w + cw > maxW && j > i) {
              break;
            }
            w += cw;
            j++;
          }
          const absStart: number = chapter.startOffset + pos + i;
          const absEnd: number = chapter.startOffset + pos + j;
          if (y + lineH > contentBottom) {
            if (lines.length > 0) {
              pages.push(new Page(chapter.idx, pageStart, pageEnd, lines));
            }
            lines = [];
            y = lc.padTopPx;
            pageStart = -1;
            pageEnd = -1;
          }
          if (pageStart === -1) {
            pageStart = absStart;
          }
          const lineText: string = (firstLine ? indentStr : '') + para.substring(i, j);
          lines.push(new LineInfo(lineText, y));
          pageEnd = absEnd;
          y += lineH;
          i = j;
          firstLine = false;
        }
        y += paraGap;
      }
      if (nl === -1) {
        break;
      }
      pos = nl + 1;
    }
    if (lines.length > 0) {
      pages.push(new Page(chapter.idx, pageStart, pageEnd, lines));
    }
    if (pages.length === 0) {
      pages.push(new Page(chapter.idx, chapter.startOffset, chapter.startOffset, []));
    }
    return pages;
  }

  static locateByOffset(pages: Page[], offset: number): number {
    for (let i = 0; i < pages.length; i++) {
      if (offset < pages[i].endOffset) {
        return i;
      }
    }
    return pages.length - 1;
  }
}

/** 章节页缓存（LRU） */
export class PageCache {
  private map: Map<number, Page[]> = new Map<number, Page[]>();
  private order: number[] = [];
  private capacity: number = 12;

  put(chapterIdx: number, pages: Page[]): void {
    const exist = this.order.indexOf(chapterIdx);
    if (exist >= 0) {
      this.order.splice(exist, 1);
    }
    this.map.set(chapterIdx, pages);
    this.order.push(chapterIdx);
    while (this.order.length > this.capacity) {
      const oldest = this.order.shift();
      if (oldest !== undefined) {
        this.map.delete(oldest);
      }
    }
  }

  get(chapterIdx: number): Page[] | null {
    const hit = this.map.get(chapterIdx);
    if (hit !== undefined) {
      return hit;
    }
    return null;
  }

  clear(): void {
    this.map.clear();
    this.order = [];
  }
}
