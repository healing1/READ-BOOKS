import { Page } from '../model/Models';

export class PageCursor {
  readonly chapterIdx: number;
  readonly pageIdx: number;

  constructor(chapterIdx: number, pageIdx: number) {
    this.chapterIdx = chapterIdx;
    this.pageIdx = pageIdx;
  }
}

/** A cache miss must load the adjacent chapter before it can mean the end of a book. */
export class PageNavigation {
  static adjacentCached(cursor: PageCursor, direction: number,
    cached: (chapterIdx: number) => Page[] | null): PageCursor | null {
    const pages: Page[] | null = cached(cursor.chapterIdx);
    if (pages === null) {
      return null;
    }
    const nextPage: number = cursor.pageIdx + (direction > 0 ? 1 : -1);
    if (nextPage >= 0 && nextPage < pages.length) {
      return new PageCursor(cursor.chapterIdx, nextPage);
    }
    const chapterIdx: number = cursor.chapterIdx + (direction > 0 ? 1 : -1);
    const adjacent: Page[] | null = cached(chapterIdx);
    return adjacent !== null && adjacent.length > 0 ?
      new PageCursor(chapterIdx, direction > 0 ? 0 : adjacent.length - 1) : null;
  }

  static async adjacent(cursor: PageCursor, direction: number, chapterCount: number,
    load: (chapterIdx: number) => Promise<Page[]>): Promise<PageCursor | null> {
    const pages: Page[] = await load(cursor.chapterIdx);
    if (pages.length === 0) {
      throw new Error('Chapter pagination is unavailable');
    }
    const nextPage: number = cursor.pageIdx + (direction > 0 ? 1 : -1);
    if (nextPage >= 0 && nextPage < pages.length) {
      return new PageCursor(cursor.chapterIdx, nextPage);
    }
    const chapterIdx: number = cursor.chapterIdx + (direction > 0 ? 1 : -1);
    if (chapterIdx < 0 || chapterIdx >= chapterCount) {
      return null;
    }
    const adjacent: Page[] = await load(chapterIdx);
    if (adjacent.length === 0) {
      throw new Error('Adjacent chapter pagination is unavailable');
    }
    return new PageCursor(chapterIdx, direction > 0 ? 0 : adjacent.length - 1);
  }

  static async turn(cursor: PageCursor, direction: number, spread: boolean, chapterCount: number,
    load: (chapterIdx: number) => Promise<Page[]>): Promise<PageCursor | null> {
    let target: PageCursor = cursor;
    const steps: number = spread ? 2 : 1;
    for (let i: number = 0; i < steps; i++) {
      const next: PageCursor | null = await PageNavigation.adjacent(target, direction, chapterCount, load);
      if (next === null) {
        // Moving back from an unaligned anchor still permits reaching the first page.
        return direction < 0 && i > 0 ? target : null;
      }
      target = next;
    }
    return target;
  }
}
