/** 实体 —— docs/DESIGN.md §6.1 */
export const MAX_CHAPTERS_PER_BOOK: number = 10000;

export class Book {
  id: number = 0;
  title: string = '';
  author: string = '';
  format: string = 'txt';
  sizeBytes: number = 0;
  encoding: string = 'utf-8';
  charCount: number = 0;
  coverColor: string = '#007AFF';
  coverPath: string = '';
  filePath: string = '';
  sourcePath: string = '';
  epubIndex: string = '';
  epubLocation: string = '';
  createdAt: number = 0;
  lastReadAt: number = 0;
  progressCharOffset: number = 0;
}

export class Chapter {
  bookId: number = 0;
  idx: number = 0;
  title: string = '';
  startOffset: number = 0;
  endOffset: number = 0;
  byteStart: number = -1;
  byteEnd: number = -1;
}

export class Bookmark {
  epubLocation: string = '';
  id: number = 0;
  bookId: number = 0;
  charOffset: number = 0;
  excerpt: string = '';
  createdAt: number = 0;
}

/** 引擎产物：页内一行（y 为画布绝对像素坐标） */
export class LineInfo {
  text: string;
  y: number;
  startOffset: number;
  endOffset: number;

  constructor(text: string, y: number, startOffset: number = -1, endOffset: number = -1) {
    this.text = text;
    this.y = y;
    this.startOffset = startOffset;
    this.endOffset = endOffset;
  }
}

export class Page {
  chapterIdx: number;
  startOffset: number;
  endOffset: number;
  lines: LineInfo[];

  constructor(chapterIdx: number, startOffset: number, endOffset: number, lines: LineInfo[]) {
    this.chapterIdx = chapterIdx;
    this.startOffset = startOffset;
    this.endOffset = endOffset;
    this.lines = lines;
  }
}
