import { taskpool } from '@kit.ArkTS';
import { Chapter, Page } from '../model/Models';
import { LayoutConstraints, Measurer, PaginationCore } from './PaginationCore';
import { paginateInBackground } from './PaginationWorker';

export { LayoutConstraints, Measurer } from './PaginationCore';

/**
 * 分页器 —— docs/DESIGN.md §5.4
 * 贪心组行：字符宽度缓存 + 视口宽度断行；段首缩进 2em、段间距 0.4 行、空行 0.8 行
 * 当前章优先，异步字宽准备 + TaskPool 纯计算；同步接口供测试和兼容调用。
 */
export class Paginator {
  static paginateChapter(text: string, chapter: Chapter, lc: LayoutConstraints, measurer: Measurer): Page[] {
    if (measurer.prepare !== undefined) {
      measurer.prepare();
    }
    return PaginationCore.paginate(text.substring(chapter.startOffset, chapter.endOffset),
      chapter.idx, chapter.startOffset, lc, measurer);
  }

  /** 每批最多 1024 字符 / 64 次原生测量后让出 UI；调用端用布局 generation 取消旧任务。 */
  static async paginateChapterAsync(text: string, chapter: Chapter, lc: LayoutConstraints,
    measurer: Measurer, isCurrent?: () => boolean): Promise<Page[]> {
    return Paginator.paginateBodyAsync(text.substring(chapter.startOffset, chapter.endOffset),
      chapter, lc, measurer, isCurrent);
  }

  /** 从磁盘单独读取的章节正文：body 是局部字符串，Page 锚点仍为全书 UTF-16 字符偏移。 */
  static async paginateBodyAsync(body: string, chapter: Chapter, lc: LayoutConstraints,
    measurer: Measurer, isCurrent?: () => boolean): Promise<Page[]> {
    const widths: Map<string, number> = new Map<string, number>();
    let pos: number = 0;
    while (pos < body.length || widths.size === 0) {
      if (isCurrent !== undefined && !isCurrent()) {
        throw new Error('Pagination request superseded');
      }
      if (measurer.prepare !== undefined) {
        measurer.prepare();
      }
      if (!widths.has('　')) {
        widths.set('　', measurer.measure('　'));
      }
      const batchEnd: number = Math.min(body.length, pos + 1024);
      let measurements: number = 0;
      while (pos < batchEnd && measurements < 64) {
        const glyph: string = PaginationCore.glyphAt(body, pos);
        if (glyph !== '\n' && !widths.has(glyph)) {
          widths.set(glyph, measurer.measure(glyph));
          measurements++;
        }
        pos += glyph.length;
      }
      if (pos < body.length) {
        await new Promise<void>((resolve: () => void) => {
          setTimeout(resolve, 0);
        });
      }
    }
    if (isCurrent !== undefined && !isCurrent()) {
      throw new Error('Pagination request superseded');
    }
    const pages: Page[] = await taskpool.execute(paginateInBackground, body, chapter.idx,
      chapter.startOffset, lc, widths) as Page[];
    if (isCurrent !== undefined && !isCurrent()) {
      throw new Error('Pagination request superseded');
    }
    return pages;
  }

  static locateByOffset(pages: Page[], offset: number): number {
    if (pages.length === 0) {
      return -1;
    }
    if (!Number.isFinite(offset) || offset <= pages[0].startOffset) {
      return 0;
    }
    let low: number = 0;
    let high: number = pages.length - 1;
    while (low < high) {
      const mid: number = Math.floor((low + high) / 2);
      if (offset < pages[mid].endOffset) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }
}

/** 双重上限的章节 LRU；只保留一章时允许超页数上限，防止大章节反复重算。 */
export class PageCache {
  private map: Map<number, Page[]> = new Map<number, Page[]>();
  private order: number[] = [];
  private capacity: number;
  private maxPages: number;
  private pageCount: number = 0;
  private pinned: Set<number> = new Set<number>();

  constructor(capacity: number = 12, maxPages: number = 240) {
    this.capacity = Math.max(1, capacity);
    this.maxPages = Math.max(1, maxPages);
  }

  /** 当前双页与即时翻页所需章节不可逐出；更换保护集合后立即恢复对旧章的淘汰。 */
  setPinned(chapterIndices: number[]): void {
    this.pinned = new Set<number>(chapterIndices);
    this.trim();
  }

  put(chapterIdx: number, pages: Page[]): void {
    const old: Page[] | undefined = this.map.get(chapterIdx);
    if (old !== undefined) {
      this.pageCount -= old.length;
    }
    const exist: number = this.order.indexOf(chapterIdx);
    if (exist >= 0) {
      this.order.splice(exist, 1);
    }
    this.map.set(chapterIdx, pages);
    this.order.push(chapterIdx);
    this.pageCount += pages.length;
    this.trim();
  }

  private trim(): void {
    while (this.order.length > this.capacity || (this.pageCount > this.maxPages && this.order.length > 1)) {
      let oldestIndex: number = -1;
      for (let i: number = 0; i < this.order.length; i++) {
        if (!this.pinned.has(this.order[i])) {
          oldestIndex = i;
          break;
        }
      }
      if (oldestIndex < 0) {
        // 上限为软限制：必需的双页/相邻章节全部被保护时不牺牲正在阅读的内容。
        break;
      }
      const oldest: number = this.order[oldestIndex];
      this.order.splice(oldestIndex, 1);
      const removed: Page[] | undefined = this.map.get(oldest);
      this.pageCount -= removed === undefined ? 0 : removed.length;
      this.map.delete(oldest);
    }
  }

  get(chapterIdx: number): Page[] | null {
    const hit = this.map.get(chapterIdx);
    if (hit !== undefined) {
      const index: number = this.order.indexOf(chapterIdx);
      if (index >= 0) {
        this.order.splice(index, 1);
      }
      this.order.push(chapterIdx);
      return hit;
    }
    return null;
  }

  clear(): void {
    this.map.clear();
    this.order = [];
    this.pageCount = 0;
    this.pinned.clear();
  }
}
