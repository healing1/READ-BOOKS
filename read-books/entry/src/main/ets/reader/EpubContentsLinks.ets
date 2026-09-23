import { Chapter } from '../model/Models';

export class ContentsLink {
  start: number;
  end: number;
  target: number;
  label: string;
  constructor(start: number, end: number, target: number, label: string) {
    this.start = start; this.end = end; this.target = target; this.label = label;
  }
}

/** Recover local TOC actions from the retained chapter index, including pre-link EPUB imports.
 * Only complete, unambiguous chapter labels on an identified contents page are linked.
 * No substring guessing, network navigation, or changes to the stored text/reading anchors.
 */
export class EpubContentsLinks {
  private targets: Map<string, Chapter> = new Map<string, Chapter>();
  private ambiguous: Set<string> = new Set<string>();
  constructor(chapters: Chapter[]) {
    chapters.forEach((chapter: Chapter) => {
      if (/（续\s*\d+）$/.test(chapter.title)) { return; }
      const key: string = EpubContentsLinks.normalize(chapter.title);
      if (key.length === 0 || /^章节\d+$/.test(key)) { return; }
      if (this.targets.has(key)) { this.ambiguous.add(key); }
      else { this.targets.set(key, chapter); }
    });
  }
  static normalize(text: string): string {
    return text.replace(/[.．·…]{2,}\s*\d+\s*$/, '').replace(/[\s\u200B\uFEFF]/g, '').toLocaleLowerCase();
  }
  static isContentsTitle(text: string): boolean {
    return /^(总?目录|目次|contents|tableofcontents)(（续\d+）)?$/.test(EpubContentsLinks.normalize(text));
  }
  resolve(chapter: Chapter, body: string): ContentsLink[] {
    const lines: string[] = body.split('\n');
    const links: ContentsLink[] = [];
    let local: number = 0;
    let nonempty: number = 0;
    let heading: boolean = EpubContentsLinks.isContentsTitle(chapter.title);
    for (let i: number = 0; i < lines.length; i++) {
      const line: string = lines[i];
      const key: string = EpubContentsLinks.normalize(line);
      if (key.length > 0) {
        nonempty++;
        if (nonempty <= 2 && EpubContentsLinks.isContentsTitle(line)) { heading = true; }
        const target: Chapter | undefined = this.targets.get(key);
        if (target !== undefined && target.idx !== chapter.idx && !this.ambiguous.has(key)) {
          links.push(new ContentsLink(chapter.startOffset + local, chapter.startOffset + local + line.length,
            target.startOffset, target.title));
        }
      }
      local += line.length + 1;
    }
    // Some old imports have only a generic spine title and no visible "目录" heading.
    const unmistakableList: boolean = /^章节\d+$/.test(EpubContentsLinks.normalize(chapter.title)) &&
      body.length < 8000 && links.length >= 3 && links.length / Math.max(1, nonempty) >= 0.75;
    return heading || unmistakableList ? links : [];
  }
}

/** Canvas-local physical pixels, recomputed after every reflow and spread change. */
export class ContentsHit {
  x: number; y: number; width: number; height: number; target: number; label: string;
  constructor(x: number, y: number, width: number, height: number, link: ContentsLink) {
    this.x = x; this.y = y; this.width = width; this.height = height;
    this.target = link.target; this.label = link.label;
  }
  contains(x: number, y: number): boolean {
    return x >= this.x && x <= this.x + this.width && y >= this.y && y <= this.y + this.height;
  }
}
