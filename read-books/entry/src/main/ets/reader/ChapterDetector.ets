import { Chapter } from '../model/Models';

/** 章节切分 —— docs/DESIGN.md §5.3 */
const CHAPTER_RE: RegExp =
  new RegExp('^(第[0-9零一二三四五六七八九十百千万两]+[章回节卷集部篇]|序章|楔子|引子|尾声|后记|Chapter\\s+\\d+)[^\n]{0,30}$');

const VIRTUAL_CHUNK: number = 50000;

export class ChapterDetector {
  static detect(text: string, bookId: number): Chapter[] {
    const headings: Chapter[] = [];
    let firstHeadingOffset: number = -1;
    let pos: number = 0;
    while (pos < text.length) {
      const nl: number = text.indexOf('\n', pos);
      const lineEnd: number = nl === -1 ? text.length : nl;
      const line: string = text.substring(pos, lineEnd).trim();
      if (line.length > 0 && CHAPTER_RE.test(line)) {
        if (firstHeadingOffset < 0) {
          firstHeadingOffset = pos;
        }
        const c = new Chapter();
        c.bookId = bookId;
        c.title = line;
        c.startOffset = pos;
        headings.push(c);
      }
      if (nl === -1) {
        break;
      }
      pos = nl + 1;
    }

    const chapters: Chapter[] = [];
    // 第一个标题前的正文 → 开篇章
    if (firstHeadingOffset > 0) {
      const pre = new Chapter();
      pre.bookId = bookId;
      pre.title = '开篇';
      pre.startOffset = 0;
      pre.endOffset = firstHeadingOffset;
      chapters.push(pre);
    }
    for (let i = 0; i < headings.length; i++) {
      const c = headings[i];
      c.endOffset = i + 1 < headings.length ? headings[i + 1].startOffset : text.length;
      chapters.push(c);
    }

    if (chapters.length === 0) {
      // 无标题 → 虚拟分章
      for (let start = 0; start < text.length; start += VIRTUAL_CHUNK) {
        const end: number = Math.min(start + VIRTUAL_CHUNK, text.length);
        const c = new Chapter();
        c.bookId = bookId;
        c.title = '片段 ' + (chapters.length + 1);
        c.startOffset = start;
        c.endOffset = end;
        chapters.push(c);
      }
    }

    for (let i = 0; i < chapters.length; i++) {
      chapters[i].idx = i;
    }
    return chapters;
  }
}
