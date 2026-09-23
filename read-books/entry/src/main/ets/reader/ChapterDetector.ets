import { Chapter, MAX_CHAPTERS_PER_BOOK } from '../model/Models';

/** 章节切分 —— docs/DESIGN.md §5.3 */
const CHAPTER_RE: RegExp =
  new RegExp('^(第[0-9零一二三四五六七八九十百千万两]+[章回节卷集部篇]|序章|楔子|引子|尾声|后记|Chapter\\s+\\d+)[^\n]{0,30}$', 'i');

const VIRTUAL_CHUNK: number = 50000;

/** The stored text is UTF-8; progress anchors remain UTF-16 string offsets. */
export function utf8ByteLength(text: string): number {
  let bytes: number = 0;
  for (let i: number = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code < 0x80) {
      bytes++;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length &&
      text.charCodeAt(i + 1) >= 0xDC00 && text.charCodeAt(i + 1) <= 0xDFFF) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

/** Retains a short candidate heading, never an entire paragraph or chapter body. */
export class StreamingChapterDetector {
  private chapters: Chapter[] = [];
  private pendingLine: string = '';
  private pendingSurrogate: string = '';
  private continuingLine: boolean = false;
  private sawHeading: boolean = false;
  private title: string = '开篇';
  private part: number = 1;
  private start: number = 0;
  private byteStart: number = 0;
  private offset: number = 0;
  private byteOffset: number = 0;
  private bookId: number;

  constructor(bookId: number = 0) {
    this.bookId = bookId;
  }

  push(chunk: string): void {
    let text: string = this.pendingSurrogate + chunk;
    this.pendingSurrogate = '';
    const last: number = text.charCodeAt(text.length - 1);
    if (last >= 0xD800 && last <= 0xDBFF) {
      this.pendingSurrogate = text.substring(text.length - 1);
      text = text.substring(0, text.length - 1);
    }
    let pos: number = 0;
    while (pos < text.length) {
      const newline: number = text.indexOf('\n', pos);
      const end: number = newline < 0 ? text.length : newline + 1;
      const fragment: string = text.substring(pos, end);
      if (!this.continuingLine && this.pendingLine.length + fragment.length <= 512) {
        this.pendingLine += fragment;
        if (newline >= 0) {
          this.consumeLine();
        }
      } else {
        this.consumeBody(this.pendingLine + fragment);
        this.pendingLine = '';
        this.continuingLine = newline < 0;
      }
      pos = end;
    }
  }

  finish(): Chapter[] {
    this.pendingLine += this.pendingSurrogate;
    this.pendingSurrogate = '';
    this.consumeLine();
    this.closeChapter();
    if (!this.sawHeading) {
      for (let i: number = 0; i < this.chapters.length; i++) {
        this.chapters[i].title = '片段 ' + (i + 1);
      }
    }
    return this.chapters;
  }

  private consumeLine(): void {
    if (this.pendingLine.length === 0) {
      return;
    }
    const heading: string = this.pendingLine.trim();
    if (!this.continuingLine && CHAPTER_RE.test(heading)) {
      this.closeChapter();
      this.sawHeading = true;
      this.title = heading;
      this.part = 1;
    }
    this.consumeBody(this.pendingLine);
    this.pendingLine = '';
    this.continuingLine = false;
  }

  private consumeBody(text: string): void {
    let pos: number = 0;
    while (pos < text.length) {
      if (this.offset - this.start >= VIRTUAL_CHUNK) {
        this.closeChapter();
        this.part++;
      }
      let end: number = Math.min(text.length, pos + VIRTUAL_CHUNK - (this.offset - this.start));
      if (end < text.length && text.charCodeAt(end - 1) >= 0xD800 && text.charCodeAt(end - 1) <= 0xDBFF &&
        text.charCodeAt(end) >= 0xDC00 && text.charCodeAt(end) <= 0xDFFF) {
        end++;
      }
      this.offset += end - pos;
      this.byteOffset += utf8ByteLength(text.substring(pos, end));
      pos = end;
    }
  }

  private closeChapter(): void {
    if (this.offset === this.start) {
      return;
    }
    if (this.chapters.length >= MAX_CHAPTERS_PER_BOOK) {
      throw new Error('章节数量不能超过 10000');
    }
    const chapter: Chapter = new Chapter();
    chapter.bookId = this.bookId;
    chapter.idx = this.chapters.length;
    chapter.title = this.part === 1 ? this.title : this.title + '（续 ' + this.part + '）';
    chapter.startOffset = this.start;
    chapter.endOffset = this.offset;
    chapter.byteStart = this.byteStart;
    chapter.byteEnd = this.byteOffset;
    this.chapters.push(chapter);
    this.start = this.offset;
    this.byteStart = this.byteOffset;
  }
}

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
        const reservedForPreface: number = firstHeadingOffset > 0 ? 1 : 0;
        if (headings.length >= MAX_CHAPTERS_PER_BOOK - reservedForPreface) {
          throw new Error('章节数量不能超过 10000');
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
      ChapterDetector.appendSlices(text, chapters, bookId, '开篇', 0, firstHeadingOffset);
    }
    for (let i = 0; i < headings.length; i++) {
      const c = headings[i];
      const endOffset: number = i + 1 < headings.length ? headings[i + 1].startOffset : text.length;
      ChapterDetector.appendSlices(text, chapters, bookId, c.title, c.startOffset, endOffset);
    }

    if (chapters.length === 0) {
      // 无标题 → 虚拟分章
      let start: number = 0;
      while (start < text.length) {
        const end: number = ChapterDetector.safeEnd(text, start, text.length);
        const c = new Chapter();
        c.bookId = bookId;
        c.title = '片段 ' + (chapters.length + 1);
        c.startOffset = start;
        c.endOffset = end;
        if (chapters.length >= MAX_CHAPTERS_PER_BOOK) {
          throw new Error('章节数量不能超过 10000');
        }
        chapters.push(c);
        start = end;
      }
    }

    for (let i = 0; i < chapters.length; i++) {
      chapters[i].idx = i;
    }
    return chapters;
  }

  private static appendSlices(text: string, chapters: Chapter[], bookId: number, title: string,
    startOffset: number, endOffset: number): void {
    let start: number = startOffset;
    let part: number = 1;
    while (start < endOffset) {
      const end: number = ChapterDetector.safeEnd(text, start, endOffset);
      if (chapters.length >= MAX_CHAPTERS_PER_BOOK) {
        throw new Error('章节数量不能超过 10000');
      }
      const chapter = new Chapter();
      chapter.bookId = bookId;
      chapter.title = part === 1 ? title : title + '（续 ' + part + '）';
      chapter.startOffset = start;
      chapter.endOffset = end;
      chapters.push(chapter);
      start = end;
      part++;
    }
  }

  private static safeEnd(text: string, start: number, endOffset: number): number {
    let end: number = Math.min(start + VIRTUAL_CHUNK, endOffset);
    if (end < endOffset && end > start && ChapterDetector.isHighSurrogate(text.charCodeAt(end - 1)) &&
      ChapterDetector.isLowSurrogate(text.charCodeAt(end))) {
      end++;
    }
    return end;
  }

  private static isHighSurrogate(code: number): boolean {
    return code >= 0xD800 && code <= 0xDBFF;
  }

  private static isLowSurrogate(code: number): boolean {
    return code >= 0xDC00 && code <= 0xDFFF;
  }
}
