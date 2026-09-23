import { describe, expect, it } from '@ohos/hypium';
import { Chapter, Page } from '../main/ets/model/Models';
import { ChapterDetector } from '../main/ets/reader/ChapterDetector';
import { EncodingDetector } from '../main/ets/reader/EncodingDetector';
import { LayoutConstraints, Measurer, PageCache, Paginator } from '../main/ets/reader/Paginator';
import { PageCursor, PageNavigation } from '../main/ets/reader/PageNavigation';
import { storageTests } from './Storage.test';
import { activityTests } from './Activity.test';
import { formatTests } from './Formats.test';
import { coverTests } from './Covers.test';

class FixedMeasurer implements Measurer {
  measure(ch: string): number {
    return 10;
  }
}

function layout(widthPx: number = 60, heightPx: number = 30): LayoutConstraints {
  return {
    widthPx: widthPx,
    heightPx: heightPx,
    padLeftPx: 0,
    padRightPx: 0,
    padTopPx: 0,
    padBottomPx: 0,
    fontSizePx: 10,
    lineHeightRatio: 1
  };
}

function chapterFor(text: string): Chapter {
  const chapter: Chapter = new Chapter();
  chapter.endOffset = text.length;
  return chapter;
}

export default function readerCoreTests(native: boolean = false): void {
  if (native) {
    storageTests();
    activityTests();
    formatTests();
    coverTests();
  }

  describe('PageNavigation', () => {
    it('loadsAnUncachedNextChapterBeforeDecidingThatTheBookEnded', 0, async () => {
      const loaded: number[] = [];
      const target: PageCursor | null = await PageNavigation.turn(new PageCursor(0, 0), 1, false, 2,
        async (ci: number): Promise<Page[]> => {
          loaded.push(ci);
          return [new Page(ci, ci * 100, (ci + 1) * 100, [])];
        });
      expect(target?.chapterIdx).assertEqual(1);
      expect(target?.pageIdx).assertEqual(0);
      expect(loaded.join(',')).assertEqual('0,1');
    });

    it('turnsASpreadAcrossTwoSinglePageChaptersAndPreparesItsRightPage', 0, async () => {
      const load = async (ci: number): Promise<Page[]> => [new Page(ci, ci * 100, (ci + 1) * 100, [])];
      const target: PageCursor | null = await PageNavigation.turn(new PageCursor(0, 0), 1, true, 4, load);
      expect(target?.chapterIdx).assertEqual(2);
      const right: PageCursor | null = await PageNavigation.adjacent(target as PageCursor, 1, 4, load);
      expect(right?.chapterIdx).assertEqual(3);
      const end: PageCursor | null = await PageNavigation.turn(target as PageCursor, 1, true, 4, load);
      expect(end).assertNull();
    });

    it('retainsAnOddFinalPageAndCanMoveBackFromAnUnalignedAnchor', 0, async () => {
      const load = async (ci: number): Promise<Page[]> => [new Page(ci, ci * 100, (ci + 1) * 100, [])];
      const target: PageCursor | null = await PageNavigation.turn(new PageCursor(0, 0), 1, true, 3, load);
      expect(target?.chapterIdx).assertEqual(2);
      expect(await PageNavigation.adjacent(target as PageCursor, 1, 3, load)).assertNull();
      const first: PageCursor | null = await PageNavigation.turn(new PageCursor(1, 0), -1, true, 3, load);
      expect(first?.chapterIdx).assertEqual(0);
      expect(await PageNavigation.turn(first as PageCursor, -1, true, 3, load)).assertNull();
    });

    it('doesNotTreatFailedChapterPaginationAsTheEndOfTheBook', 0, async () => {
      let rejected: boolean = false;
      try {
        await PageNavigation.turn(new PageCursor(0, 0), 1, false, 2,
          async (ci: number): Promise<Page[]> => ci === 0 ? [new Page(0, 0, 100, [])] : []);
      } catch (e) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });

  describe('EncodingDetector', () => {
    it('detectsSupportedByteOrderMarks', 0, () => {
      expect(EncodingDetector.detect(new Uint8Array([0xEF, 0xBB, 0xBF, 0x41]))).assertEqual('utf-8');
      expect(EncodingDetector.detect(new Uint8Array([0xFF, 0xFE, 0x41, 0]))).assertEqual('utf-16le');
      expect(EncodingDetector.detect(new Uint8Array([0xFE, 0xFF, 0, 0x41]))).assertEqual('utf-16be');
    });

    it('rejectsUtf32AndIncompleteUtf16', 0, () => {
      const samples: Uint8Array[] = [new Uint8Array([0xFF, 0xFE, 0, 0]),
        new Uint8Array([0, 0, 0xFE, 0xFF]), new Uint8Array([0xFF, 0xFE, 0x41])];
      samples.forEach((bytes: Uint8Array) => {
        let rejected: boolean = false;
        try {
          EncodingDetector.detect(bytes);
        } catch (e) {
          rejected = true;
        }
        expect(rejected).assertTrue();
      });
    });

    it('rejectsBlankAndBinaryContentButAcceptsReadableText', 0, () => {
      const samples: string[] = [' \n\t', '标题\u0000正文', '正文\u0001\u0002\u0003'];
      samples.forEach((value: string) => {
        let rejected: boolean = false;
        try {
          EncodingDetector.validateText(value);
        } catch (e) {
          rejected = true;
        }
        expect(rejected).assertTrue();
      });
      EncodingDetector.validateText('第一章\n\t正文与 English 123');
    });

    it('checksUtf8BeyondTheFormer64KiBSample', 0, () => {
      const bytes: Uint8Array = new Uint8Array(65538);
      bytes.fill(0x41);
      bytes[65536] = 0x81;
      bytes[65537] = 0x40;

      expect(EncodingDetector.detect(bytes)).assertEqual('gb18030');
    });
  });

  describe('ChapterDetector', () => {
    it('doesNotSplitSurrogatePairsAtVirtualChapterBoundaries', 0, () => {
      const text: string = '字'.repeat(49999) + '😀后续';
      const chapters: Chapter[] = ChapterDetector.detect(text, 4);
      expect(chapters.length).assertEqual(2);
      expect(chapters[0].endOffset).assertEqual(50001);
      expect(chapters[1].startOffset).assertEqual(50001);
      expect(text.substring(chapters[0].startOffset, chapters[0].endOffset).endsWith('😀')).assertTrue();
    });

    it('detectsChineseAndCaseInsensitiveEnglishHeadings', 0, () => {
      const text: string = '序言\n第一章 开始\n正文\nchapter 2 Continue\n结尾';
      const chapters: Chapter[] = ChapterDetector.detect(text, 7);
      const firstHeading: number = text.indexOf('第一章');
      const secondHeading: number = text.indexOf('chapter 2');

      expect(chapters.length).assertEqual(3);
      expect(chapters[0].title).assertEqual('开篇');
      expect(chapters[0].startOffset).assertEqual(0);
      expect(chapters[0].endOffset).assertEqual(firstHeading);
      expect(chapters[1].title).assertEqual('第一章 开始');
      expect(chapters[1].startOffset).assertEqual(firstHeading);
      expect(chapters[1].endOffset).assertEqual(secondHeading);
      expect(chapters[2].title).assertEqual('chapter 2 Continue');
      expect(chapters[2].endOffset).assertEqual(text.length);
    });

    it('createsVirtualChaptersForBooksWithoutHeadings', 0, () => {
      const text: string = '字'.repeat(100001);
      const chapters: Chapter[] = ChapterDetector.detect(text, 9);

      expect(chapters.length).assertEqual(3);
      expect(chapters[0].startOffset).assertEqual(0);
      expect(chapters[0].endOffset).assertEqual(50000);
      expect(chapters[1].startOffset).assertEqual(50000);
      expect(chapters[1].endOffset).assertEqual(100000);
      expect(chapters[2].startOffset).assertEqual(100000);
      expect(chapters[2].endOffset).assertEqual(100001);
    });

    it('rejectsAnExcessiveNumberOfChapterHeadings', 0, () => {
      let rejected: boolean = false;
      try {
        ChapterDetector.detect('第一章\n'.repeat(10001), 1);
      } catch (e) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('splitsOversizedDetectedChapters', 0, () => {
      const text: string = '第一章 开始\n' + '字'.repeat(100001);
      const chapters: Chapter[] = ChapterDetector.detect(text, 2);

      expect(chapters.length).assertEqual(3);
      expect(chapters[0].title).assertEqual('第一章 开始');
      expect(chapters[1].title).assertEqual('第一章 开始（续 2）');
      expect(chapters[0].endOffset - chapters[0].startOffset <= 50000).assertTrue();
      expect(chapters[1].endOffset - chapters[1].startOffset <= 50000).assertTrue();
      expect(chapters[2].endOffset).assertEqual(text.length);
    });
  });

  describe('Paginator', () => {
    it('cancelsWidthPreparationWhenTheLayoutRequestIsSuperseded', 0, async () => {
      let rejected: boolean = false;
      const chapter: Chapter = chapterFor('正文'.repeat(3000));
      let requests: number = 0;
      try {
        await Paginator.paginateBodyAsync('正文'.repeat(3000), chapter, layout(), new FixedMeasurer(), () => {
          requests++;
          return requests < 2;
        });
      } catch (e) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect(requests).assertEqual(2);
    });

    if (native) {
      it('paginatesALocalChapterBodyUsingAbsoluteBookOffsets', 0, async () => {
      const prefix: string = '前文'.repeat(1000);
      const body: string = '章节正文😀，English words。\n'.repeat(20);
      const chapter: Chapter = new Chapter();
      chapter.idx = 7;
      chapter.startOffset = prefix.length;
      chapter.endOffset = prefix.length + body.length;
      const pages: Page[] = await Paginator.paginateBodyAsync(body, chapter, layout(80, 30), new FixedMeasurer());
      const expected: Page[] = Paginator.paginateChapter(prefix + body, chapter, layout(80, 30), new FixedMeasurer());
      expect(pages.length).assertEqual(expected.length);
      expect(pages[0].chapterIdx).assertEqual(7);
      expect(pages[0].startOffset).assertEqual(prefix.length);
      expect(pages[pages.length - 1].endOffset).assertEqual(chapter.endOffset);
      for (let i: number = 0; i < pages.length; i++) {
        expect(pages[i].startOffset).assertEqual(expected[i].startOffset);
        expect(pages[i].endOffset).assertEqual(expected[i].endOffset);
        expect(pages[i].lines.map((line) => line.text).join('\n'))
          .assertEqual(expected[i].lines.map((line) => line.text).join('\n'));
      }
    });

    }

    it('keepsOrdinaryEnglishWordsTogether', 0, () => {
      const text: string = 'one two three';
      const pages: Page[] = Paginator.paginateChapter(text, chapterFor(text), layout(80, 80), new FixedMeasurer());
      expect(pages[0].lines[0].text).assertEqual('　　one ');
      expect(pages[0].lines[1].text).assertEqual('two ');
      expect(pages[0].lines[2].text).assertEqual('three');
    });

    it('keepsClosingPunctuationOffTheStartOfWrappedLines', 0, () => {
      const text: string = '甲乙丙，丁戊己。';
      const pages: Page[] = Paginator.paginateChapter(text, chapterFor(text), layout(50, 80), new FixedMeasurer());
      expect(pages[0].lines[0].text).assertEqual('　　甲乙');
      expect(pages[0].lines[1].text.startsWith('丙，')).assertTrue();
      pages[0].lines.forEach((line) => {
        expect(line.text.startsWith('，') || line.text.startsWith('。')).assertFalse();
      });
    });

    it('movesAWholeEnglishWordWithItsClosingPunctuation', 0, () => {
      const text: string = '甲hello,world';
      const pages: Page[] = Paginator.paginateChapter(text, chapterFor(text), layout(80, 80), new FixedMeasurer());
      expect(pages[0].lines[0].text).assertEqual('　　甲');
      expect(pages[0].lines[1].text).assertEqual('hello,');
      expect(pages[0].lines[2].text).assertEqual('world');
    });

    it('neverSplitsEmojiSurrogatePairsAcrossLinesOrPages', 0, () => {
      const text: string = '😀😀😀😀😀';
      const pages: Page[] = Paginator.paginateChapter(text, chapterFor(text), layout(30, 10), new FixedMeasurer());
      expect(pages[0].lines[0].text).assertEqual('　　😀');
      let restored: string = '';
      pages.forEach((page: Page) => {
        expect(page.startOffset % 2).assertEqual(0);
        expect(page.endOffset % 2).assertEqual(0);
        page.lines.forEach((line) => {
          restored += line.text.replace('　　', '');
        });
      });
      expect(restored).assertEqual(text);
    });

    it('assignsEveryWhitespaceAndBoundaryOffsetToOnePage', 0, () => {
      const text: string = '\n甲乙丙丁\n\n戊己庚辛\n';
      const pages: Page[] = Paginator.paginateChapter(text, chapterFor(text), layout(40, 20), new FixedMeasurer());
      expect(pages[0].startOffset).assertEqual(0);
      expect(pages[pages.length - 1].endOffset).assertEqual(text.length);
      for (let i: number = 0; i < pages.length - 1; i++) {
        expect(pages[i].endOffset).assertEqual(pages[i + 1].startOffset);
        expect(Paginator.locateByOffset(pages, pages[i].endOffset)).assertEqual(i + 1);
      }
      for (let offset: number = 0; offset < text.length; offset++) {
        const page: Page = pages[Paginator.locateByOffset(pages, offset)];
        expect(page.startOffset <= offset && page.endOffset > offset).assertTrue();
      }
      expect(Paginator.locateByOffset(pages, -99)).assertEqual(0);
      expect(Paginator.locateByOffset(pages, text.length + 99)).assertEqual(pages.length - 1);
      expect(Paginator.locateByOffset([], 0)).assertEqual(-1);
    });

    it('retainsTheCharacterAnchorWhenPageWidthChanges', 0, () => {
      const text: string = '阅读正文'.repeat(200);
      const chapter: Chapter = chapterFor(text);
      const wide: Page[] = Paginator.paginateChapter(text, chapter, layout(120, 60), new FixedMeasurer());
      const narrow: Page[] = Paginator.paginateChapter(text, chapter, layout(60, 60), new FixedMeasurer());
      const anchor: number = wide[3].startOffset;
      const restored: Page = narrow[Paginator.locateByOffset(narrow, anchor)];
      expect(restored.startOffset <= anchor && restored.endOffset > anchor).assertTrue();
      expect(wide[wide.length - 1].endOffset).assertEqual(narrow[narrow.length - 1].endOffset);
    });

    it('handlesBlankChaptersAndInvalidViewportWithoutLooping', 0, () => {
      const text: string = '\n\n\n';
      const pages: Page[] = Paginator.paginateChapter(text, chapterFor(text), layout(), new FixedMeasurer());
      expect(pages.length).assertEqual(1);
      expect(pages[0].endOffset).assertEqual(text.length);
      expect(pages[0].lines.length).assertEqual(0);
      expect(Paginator.paginateChapter('正文', chapterFor('正文'), layout(0), new FixedMeasurer()).length).assertEqual(0);
      expect(Paginator.paginateChapter('正文', chapterFor('正文'), layout(60, 1), new FixedMeasurer()).length).assertEqual(0);
    });

    it('paginatesUsingMeasuredCharacterWidths', 0, () => {
      const chapter = new Chapter();
      chapter.idx = 2;
      chapter.startOffset = 0;
      chapter.endOffset = 10;
      const constraints: LayoutConstraints = {
        widthPx: 60,
        heightPx: 30,
        padLeftPx: 0,
        padRightPx: 0,
        padTopPx: 0,
        padBottomPx: 0,
        fontSizePx: 10,
        lineHeightRatio: 1
      };

      const pages: Page[] = Paginator.paginateChapter('abcdefghij', chapter, constraints, new FixedMeasurer());

      expect(pages.length).assertEqual(1);
      expect(pages[0].chapterIdx).assertEqual(2);
      expect(pages[0].startOffset).assertEqual(0);
      expect(pages[0].endOffset).assertEqual(10);
      expect(pages[0].lines.length).assertEqual(2);
      expect(pages[0].lines[0].text).assertEqual('　　abcd');
      expect(pages[0].lines[1].text).assertEqual('efghij');
    });

    it('updatesRecencyWhenPageCacheIsRead', 0, () => {
      const cache = new PageCache();
      for (let i: number = 0; i < 12; i++) {
        cache.put(i, [new Page(i, 0, 1, [])]);
      }

      expect(cache.get(0) === null).assertFalse();
      cache.put(12, [new Page(12, 0, 1, [])]);

      expect(cache.get(1)).assertNull();
      expect(cache.get(0) === null).assertFalse();
      expect(cache.get(12) === null).assertFalse();
    });

    it('boundsTotalCachedPagesAndAccountsForReplacement', 0, () => {
      const cache: PageCache = new PageCache(12, 3);
      cache.put(0, [new Page(0, 0, 1, []), new Page(0, 1, 2, [])]);
      cache.put(1, [new Page(1, 2, 3, [])]);
      cache.put(0, [new Page(0, 0, 2, [])]);
      cache.put(2, [new Page(2, 3, 4, [])]);
      expect(cache.get(1) === null).assertFalse();
      cache.put(3, [new Page(3, 4, 5, []), new Page(3, 5, 6, [])]);
      expect(cache.get(0)).assertNull();
      expect(cache.get(2)).assertNull();
      expect(cache.get(1) === null).assertFalse();
      expect(cache.get(3) === null).assertFalse();
      cache.clear();
      expect(cache.get(3)).assertNull();
    });

    it('neverEvictsPinnedSpreadChaptersOverTheSoftPageBudget', 0, () => {
      const cache: PageCache = new PageCache(2, 3);
      const huge: Page[] = [];
      for (let i: number = 0; i < 300; i++) {
        huge.push(new Page(0, i, i + 1, []));
      }
      cache.setPinned([0, 1]);
      cache.put(0, huge);
      cache.put(1, [new Page(1, 300, 301, [])]);
      cache.put(2, [new Page(2, 301, 302, [])]);
      expect(cache.get(0)?.length).assertEqual(300);
      expect(cache.get(1) === null).assertFalse();
      expect(cache.get(2)).assertNull();

      cache.setPinned([1, 2]);
      expect(cache.get(0)).assertNull();
      cache.put(2, [new Page(2, 301, 302, [])]);
      expect(cache.get(1) === null).assertFalse();
      expect(cache.get(2) === null).assertFalse();
    });

    it('releasesPinsWhenTheLayoutCacheIsCleared', 0, () => {
      const cache: PageCache = new PageCache(1, 1);
      cache.setPinned([0, 1]);
      cache.put(0, [new Page(0, 0, 1, [])]);
      cache.put(1, [new Page(1, 1, 2, [])]);
      expect(cache.get(0) === null).assertFalse();
      expect(cache.get(1) === null).assertFalse();
      cache.clear();
      cache.put(0, [new Page(0, 0, 1, [])]);
      cache.put(1, [new Page(1, 1, 2, [])]);
      expect(cache.get(0)).assertNull();
      expect(cache.get(1) === null).assertFalse();
    });
  });
}
