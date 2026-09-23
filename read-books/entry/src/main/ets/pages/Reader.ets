import { router, mediaquery, LengthMetricsUnit, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Book, Bookmark, Chapter, Page } from '../model/Models';
import { ReadingSettings } from '../model/ReadingSettings';
import { ReadingFonts } from '../reader/ReadingFonts';
import { AppPreferences } from '../model/AppPreferences';
import { BookRepo } from '../data/BookRepo';
import { BookmarkRepo } from '../data/BookmarkRepo';
import { ChapterRepo } from '../data/ChapterRepo';
import { ReadingActivityRepo } from '../data/ReadingActivityRepo';
import { ImportService } from '../reader/ImportService';
import { Paginator, PageCache, Measurer, LayoutConstraints } from '../reader/Paginator';
import { PageCursor, PageNavigation } from '../reader/PageNavigation';
import { ReadingSession } from '../reader/ReadingSession';
import { ThemeManager, ReadingPalette } from '../theme/ThemeManager';
import { HudTopBar, HudBottomBar } from '../components/HudBar';
import { IconButton } from '../components/IconButton';
import { ReadingSettingsPanel } from '../components/ReadingSettingsPanel';
import { ReadingContentsPanel } from '../components/ReadingContentsPanel';
import { WindowMode } from '../utils/WindowMode';
import { EpubContentsLinks, ContentsLink, ContentsHit } from '../reader/EpubContentsLinks';
import { ReadingAssets } from '../reader/ReadingAssets';
import { Spacing, TypeScale, Radius } from '../theme/tokens';
import { ReaderMotion } from '../theme/ReaderMotion';
import { ReadingRefresh } from '../theme/ReadingRefresh';

const READER_SINGLE_MAX_WIDTH: number = 800;
const READER_SPREAD_MAX_WIDTH: number = 1360;
const READER_SPREAD_GUTTER: number = 48;

/** Each async request owns a fixed font snapshot: footer painting must not change measurement. */
class CanvasMeasurer implements Measurer {
  private ctx: CanvasRenderingContext2D;
  private font: string;
  private cache: Map<string, number> = new Map<string, number>();

  constructor(ctx: CanvasRenderingContext2D, fontPx: number, family: string = 'sans-serif') {
    this.ctx = ctx;
    this.font = fontPx + 'px ' + family;
  }

  prepare(): void {
    this.ctx.font = this.font;
  }

  measure(ch: string): number {
    const hit = this.cache.get(ch);
    if (hit !== undefined) {
      return hit;
    }
    this.prepare();
    const width: number = this.ctx.measureText(ch).width;
    this.cache.set(ch, width);
    return width;
  }
}

/** Native TXT reader: character anchors, cancellable pagination, continuous tablet spreads. */
@Entry
@ComponentV2
struct Reader {
  @Local book: Book = new Book();
  @Local chapters: Chapter[] = [];
  @Local pages: Page[] = [];
  @Local pageIdx: number = 0;
  @Local currentChapterIdx: number = -1;
  @Local hudVisible: boolean = false;
  @Local panelVisible: boolean = false;
  @Local panelKind: string = 'contents';
  @Local outlineBusy: boolean = false;
  @Local bookmarks: Bookmark[] = [];
  @Local bookmarkBusy: boolean = false;
  @Local isDark: boolean = false;
  @Local ready: boolean = false;
  @Local busy: boolean = true;
  @Local navigationPending: boolean = false;
  @Local errorMessage: string = '';
  @Local sliderValue: number = 0;
  @Local sliderPreview: boolean = false;
  @Local spreadMode: boolean = false;
  @Local wideWindow: boolean = false;
  @Local dragX: number = 0;
  @Local previewX: number = 0;
  @Local previewVisible: boolean = false;
  @Local indexedChapters: number = 0;
  @Local totalPages: number = 0;
  @Local safeTop: number = 0;
  @Local safeBottom: number = 0;
  @Local visibleContentsLinks: ContentsHit[] = [];
  @Local paperOpacity: number = 0;

  @Local settings: ReadingSettings = ReadingSettings.load();
  private preferences: AppPreferences = AppPreferences.load();
  private ctx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  private previewCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  private canvasReady: boolean = false;
  private immersiveReady: boolean = false;
  private firstFramePublished: boolean = false;
  private previewReady: boolean = false;
  private cache: PageCache = new PageCache();
  private inlineContents: EpubContentsLinks = new EpubContentsLinks([]);
  private chapterLinks: Map<number, ContentsLink[]> = new Map<number, ContentsLink[]>();
  private paintedLinks: ContentsHit[] = [];
  private pageCounts: number[] = [];
  private pendingPages: Map<number, Promise<Page[]>> = new Map<number, Promise<Page[]>>();
  private darkListener: mediaquery.MediaQueryListener | null = null;
  private readerWindow: window.Window | null = null;
  private positionOffset: number = 0;
  private pendingProgressOffset: number = -1;
  private progressWriteActive: boolean = false;
  private progressTask: Promise<void> = Promise.resolve();
  private leaving: boolean = false;
  private backgroundEpoch: number = 0;
  private backgroundRunning: boolean = false;
  private backgroundFailed: Set<number> = new Set<number>();
  private indexCursor: number = 0;
  private active: boolean = true;
  private foreground: boolean = true;
  private readingSession: ReadingSession = new ReadingSession();
  private refresh: ReadingRefresh = new ReadingRefresh();
  private completionRecorded: boolean = false;
  private generation: number = 0;
  private navigationRequest: number = 0;
  private layoutTimer: number = -1;
  private indexTimer: number = -1;
  private heartbeat: number = -1;
  private animationTimer: number = -1;
  private animationEpoch: number = 0;
  private animating: boolean = false;
  private previewCursor: PageCursor | null = null;
  private previewDirection: number = 0;
  private windowEvent = (event: window.WindowEventType): void => {
    if (event === window.WindowEventType.WINDOW_HIDDEN) {
      this.setForeground(false);
      this.saveProgress();
    } else if (event === window.WindowEventType.WINDOW_SHOWN) {
      this.setForeground(true);
    }
  };

  aboutToAppear(): void {
    try { ReadingAssets.register(this.getUIContext(), this.settings); } catch (_) {}
    this.active = true;
    this.darkListener = mediaquery.matchMediaSync('(prefers-color-scheme: dark)');
    this.isDark = this.darkListener.matches;
    this.darkListener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.isDark = result.matches;
      this.draw();
    });
    this.init();
    this.heartbeat = setInterval(() => {
      this.saveProgress();
      this.readingSession.flush().catch(() => {});
    }, 30000);
  }

  onPageShow(): void {
    this.setForeground(true);
  }

  pageTransition() {
    PageTransitionEnter(ReaderMotion.pageEnter(this.settings.reduceMotion))
      .opacity(this.settings.reduceMotion ? 1 : 0)
      .translate({ y: this.settings.reduceMotion ? 0 : 20 })
      .scale({ x: this.settings.reduceMotion ? 1 : 0.985, y: this.settings.reduceMotion ? 1 : 0.985 })
      .onEnter((_type: RouteType, progress: number) => {
        // Keep the outgoing shelf's safe area stable until it is no longer visible.
        if (progress >= 1 && this.active && !this.leaving && this.readerWindow === null) {
          this.enterImmersiveMode();
        }
      })
    PageTransitionExit(ReaderMotion.pageExit(this.settings.reduceMotion))
      .opacity(this.settings.reduceMotion ? 1 : 0)
      .translate({ y: this.settings.reduceMotion ? 0 : 16 })
  }

  onPageHide(): void {
    this.setForeground(false);
    this.saveProgress();
  }

  private setForeground(visible: boolean): void {
    if (!visible) { this.refresh.stop(); }
    this.foreground = visible;
    if (visible) {
      this.resumeReading();
      if (this.ready && this.currentChapterIdx >= 0) {
        this.scheduleBackground();
      }
    } else {
      this.readingSession.pause().catch(() => {});
      this.backgroundEpoch++;
      clearTimeout(this.indexTimer);
      this.cancelMotion();
    }
  }

  private resumeReading(): void {
    if (this.active && this.foreground && this.ready && !this.busy && !this.panelVisible &&
      this.errorMessage.length === 0) {
      this.readingSession.resume();
    }
  }

  onBackPress(): boolean {
    if (this.panelVisible) {
      this.panelVisible = false;
      return true;
    }
    this.backToShelf();
    return true;
  }

  aboutToDisappear(): void {
    this.refresh.dispose();
    this.setForeground(false);
    this.saveProgress();
    this.active = false;
    this.generation++;
    this.navigationRequest++;
    this.animationEpoch++;
    clearTimeout(this.layoutTimer);
    clearTimeout(this.indexTimer);
    clearTimeout(this.animationTimer);
    clearInterval(this.heartbeat);
    this.darkListener?.off('change');
    this.leaveImmersiveMode();
  }

  private async enterImmersiveMode(): Promise<void> {
    try {
      const win = await window.getLastWindow(getContext(this) as common.UIAbilityContext);
      if (!this.active) {
        return;
      }
      this.readerWindow = win;
      this.wideWindow = px2vp(win.getWindowProperties().windowRect.width) >= 1000;
      this.spreadMode = this.wideWindow && this.settings.layoutMode === 'double';
      const cutout = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      this.safeTop = px2vp(cutout.topRect.height);
      this.safeBottom = px2vp(cutout.bottomRect.height);
      win.on('windowEvent', this.windowEvent);
      await WindowMode.setReaderMode(win, true);
    } catch (e) {
      // Split-screen may prohibit immersive mode; the safe-area layout remains usable.
    }
    if (this.active && !this.leaving) {
      this.immersiveReady = true;
      this.scheduleLayout(80);
    }
  }

  private async leaveImmersiveMode(): Promise<void> {
    const win = this.readerWindow;
    if (win === null) {
      return;
    }
    this.readerWindow = null;
    try {
      win.off('windowEvent', this.windowEvent);
      await WindowMode.setReaderMode(win, false);
    } catch (e) {}
  }

  private async init(): Promise<void> {
    this.busy = true;
    this.errorMessage = '';
    try {
      const params = router.getParams() as Record<string, Object>;
      const bookId: number = params !== undefined ? (params['bookId'] as number) : 0;
      const book = await BookRepo.getById(bookId);
      if (book === null) {
        throw new Error('这本书已不在书架中，请返回书架重新导入。');
      }
      const chapters = await ImportService.ensureChapterIndex(book, await ChapterRepo.listByBook(bookId));
      if (!this.active) {
        return;
      }
      if (chapters.length === 0 || book.charCount === 0) {
        throw new Error('没有找到可阅读的正文，请重新导入这本书。');
      }
      this.book = book;
      this.chapters = chapters;
      this.inlineContents = new EpubContentsLinks(chapters);
      this.positionOffset = Math.max(0, Math.min(book.progressCharOffset, book.charCount - 1));
      this.ready = true;
      this.bookmarks = await BookmarkRepo.listByBook(bookId);
      this.scheduleLayout();
    } catch (e) {
      if (this.active) {
        this.busy = false;
        this.errorMessage = e instanceof Error ? e.message : '暂时无法打开图书，请重试。';
      }
    }
  }

  private chapterForOffset(offset: number): number {
    let lo: number = 0;
    let hi: number = this.chapters.length - 1;
    while (lo < hi) {
      const mid = Math.floor((lo + hi) / 2);
      if (offset < this.chapters[mid].endOffset) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  private constraints(): LayoutConstraints {
    const gutter: number = this.spreadMode ? vp2px(READER_SPREAD_GUTTER) : 0;
    return {
      widthPx: Math.max(1, this.spreadMode ? (this.ctx.width - gutter) / 2 :
        Math.min(this.ctx.width, vp2px(READER_SINGLE_MAX_WIDTH))),
      heightPx: this.ctx.height,
      padLeftPx: vp2px(this.spreadMode ? 32 : 24),
      padRightPx: vp2px(this.spreadMode ? 32 : 24),
      padTopPx: vp2px(60 + this.safeTop),
      padBottomPx: vp2px(48 + this.safeBottom),
      fontSizePx: fp2px(this.settings.fontSize),
      lineHeightRatio: this.settings.lineHeight
    };
  }

  private recordPageCount(chapterIdx: number, count: number): void {
    const previous: number = this.pageCounts[chapterIdx] ?? 0;
    if (previous === count) {
      return;
    }
    this.pageCounts[chapterIdx] = count;
    this.totalPages += count - previous;
    if (previous === 0) {
      this.indexedChapters++;
    }
  }

  private async loadChapter(chapterIdx: number, generation: number): Promise<Page[]> {
    if (chapterIdx < 0 || chapterIdx >= this.chapters.length) {
      return [];
    }
    const hit = this.cache.get(chapterIdx);
    if (hit !== null) {
      return hit;
    }
    const pending = this.pendingPages.get(chapterIdx);
    if (pending !== undefined) {
      return pending;
    }
    const constraints = this.constraints();
    const measure = new CanvasMeasurer(this.ctx, constraints.fontSizePx, ReadingFonts.family(this.settings));
    const task = this.paginateChapterBody(chapterIdx, generation, constraints, measure);
    this.pendingPages.set(chapterIdx, task);
    try {
      const pages = await task;
      if (!this.active || generation !== this.generation) {
        return [];
      }
      this.recordPageCount(chapterIdx, pages.length);
      return pages;
    } finally {
      if (generation === this.generation) {
        this.pendingPages.delete(chapterIdx);
      }
    }
  }

  private async paginateChapterBody(chapterIdx: number, generation: number,
    constraints: LayoutConstraints, measure: Measurer): Promise<Page[]> {
    const chapter: Chapter = this.chapters[chapterIdx];
    const body: string = await ImportService.readChapter(this.book, chapter);
    if (this.book.format === 'epub' && this.active && generation === this.generation && !this.chapterLinks.has(chapterIdx)) {
      const links: ContentsLink[] = this.inlineContents.resolve(chapter, body);
      if (links.length > 0) { this.chapterLinks.set(chapterIdx, links); }
    }
    return Paginator.paginateBodyAsync(body, chapter, constraints, measure,
      () => this.active && generation === this.generation);
  }

  private scheduleBackground(): void {
    this.backgroundEpoch++;
    this.backgroundFailed.clear();
    clearTimeout(this.indexTimer);
    const epoch: number = this.backgroundEpoch;
    const generation: number = this.generation;
    if (this.foreground) {
      this.indexTimer = setTimeout(() => this.runBackground(generation, epoch), 350);
    }
  }

  private async runBackground(generation: number, epoch: number): Promise<void> {
    if (!this.active || !this.foreground || generation !== this.generation || epoch !== this.backgroundEpoch) {
      return;
    }
    if (this.backgroundRunning || this.busy || this.navigationPending || this.animating) {
      this.indexTimer = setTimeout(() => this.runBackground(generation, epoch), 600);
      return;
    }
    this.backgroundRunning = true;
    let next: number = -1;
    let continueWork: boolean = false;
    try {
      // Each idle slice prepares one bounded chapter. User navigation takes priority.
      const offsets: number[] = [1, -1, 2, 3, -2];
      for (let i: number = 0; i < offsets.length; i++) {
        const ci: number = this.currentChapterIdx + offsets[i];
        if (ci >= 0 && ci < this.chapters.length && !this.backgroundFailed.has(ci) &&
          this.cache.get(ci) === null) {
          next = ci;
          break;
        }
      }
      const neighbor: boolean = next >= 0;
      while (next < 0 && this.indexCursor < this.chapters.length) {
        const ci: number = this.indexCursor++;
        if ((this.pageCounts[ci] ?? 0) === 0) {
          next = ci;
        }
      }
      if (next < 0) {
        return;
      }
      continueWork = true;
      const pages: Page[] = await this.loadChapter(next, generation);
      if (this.active && generation === this.generation && epoch === this.backgroundEpoch && neighbor) {
        this.cache.put(next, pages);
      }
    } catch (e) {
      // Foreground navigation retries a failed chapter and presents its actionable error.
      this.backgroundFailed.add(next);
    } finally {
      this.backgroundRunning = false;
      if (this.active && generation === this.generation && epoch === this.backgroundEpoch &&
        continueWork) {
        this.indexTimer = setTimeout(() => this.runBackground(generation, epoch), 600);
      }
    }
  }

  private scheduleLayout(delay: number = 0): void {
    if (!this.ready || !this.canvasReady || !this.immersiveReady || this.leaving) {
      return;
    }
    this.generation++;
    this.navigationRequest++;
    this.navigationPending = false;
    this.backgroundEpoch++;
    this.cancelMotion();
    this.cache.clear();
    this.pendingPages.clear();
    this.pageCounts = [];
    this.indexedChapters = 0;
    this.totalPages = 0;
    this.indexCursor = 0;
    this.busy = true;
    this.visibleContentsLinks = [];
    this.readingSession.pause().catch(() => {});
    clearTimeout(this.layoutTimer);
    clearTimeout(this.indexTimer);
    // Canvas dimensions settle after breakpoint/safe-area updates.
    this.layoutTimer = setTimeout(() => {
      this.navigateToOffset(this.positionOffset);
    }, this.firstFramePublished ? delay : Math.max(80, delay));
  }

  private async navigateToOffset(offset: number): Promise<void> {
    if (!this.ready || !this.canvasReady || !this.active) {
      return;
    }
    const request: number = ++this.navigationRequest;
    const generation: number = this.generation;
    const anchor: number = Math.max(0, Math.min(offset, this.book.charCount - 1));
    const ci: number = this.chapterForOffset(anchor);
    this.busy = true;
    this.readingSession.pause().catch(() => {});
    this.navigationPending = false;
    this.backgroundEpoch++;
    clearTimeout(this.indexTimer);
    this.sliderPreview = false;
    this.cancelMotion();
    try {
      const pages = await this.loadChapter(ci, generation);
      if (!this.active || request !== this.navigationRequest || generation !== this.generation) {
        return;
      }
      if (pages.length === 0) {
        throw new Error('当前窗口太小，无法显示正文。请扩大窗口后重试。');
      }
      this.pinNeighborhood(ci);
      this.cache.put(ci, pages);
      this.pages = pages;
      this.pageIdx = Paginator.locateByOffset(pages, anchor);
      this.currentChapterIdx = ci;
      this.positionOffset = anchor;
      await this.ensureScene(new PageCursor(ci, this.pageIdx), generation);
      if (!this.active || request !== this.navigationRequest || generation !== this.generation) {
        return;
      }
      this.busy = false;
      this.errorMessage = '';
      this.draw();
      if (!this.firstFramePublished) {
        this.firstFramePublished = true;
          this.getUIContext().animateTo({ duration: this.settings.reduceMotion ? 0 : 180, curve: Curve.EaseOut,
            expectedFrameRateRange: this.settings.reduceMotion ? undefined : ReadingRefresh.range() }, () => {
          this.paperOpacity = 1;
        });
      }
      this.syncSlider();
      this.saveProgress();
      this.resumeReading();
      this.recordCompletion();
      this.scheduleBackground();
    } catch (e) {
      if (this.active && request === this.navigationRequest && generation === this.generation) {
        this.busy = false;
        this.errorMessage = e instanceof Error ? e.message : '排版暂时失败，请重试。';
      }
    }
  }

  private currentCursor(): PageCursor | null {
    return this.currentChapterIdx >= 0 && this.pages.length > 0 ?
      new PageCursor(this.currentChapterIdx, this.pageIdx) : null;
  }

  private pinNeighborhood(chapterIdx: number): void {
    const pinned: number[] = [];
    for (let ci: number = Math.max(0, chapterIdx - 2); ci <= Math.min(this.chapters.length - 1, chapterIdx + 3); ci++) {
      pinned.push(ci);
    }
    this.cache.setPinned(pinned);
  }

  private adjacentCursor(cursor: PageCursor, direction: number): PageCursor | null {
    return PageNavigation.adjacentCached(cursor, direction, (ci: number) => this.cache.get(ci));
  }

  private async loadForNavigation(chapterIdx: number, generation: number): Promise<Page[]> {
    const pages: Page[] = await this.loadChapter(chapterIdx, generation);
    if (!this.active || generation !== this.generation) {
      throw new Error('Navigation request superseded');
    }
    this.cache.put(chapterIdx, pages);
    return pages;
  }

  private async ensureScene(cursor: PageCursor, generation: number): Promise<void> {
    if (this.spreadMode) {
      await PageNavigation.adjacent(cursor, 1, this.chapters.length,
        (ci: number) => this.loadForNavigation(ci, generation));
    }
  }

  private sceneReady(cursor: PageCursor): boolean {
    const pages: Page[] | null = this.cache.get(cursor.chapterIdx);
    if (pages === null) {
      return false;
    }
    return !this.spreadMode || cursor.pageIdx + 1 < pages.length ||
      cursor.chapterIdx + 1 === this.chapters.length || this.cache.get(cursor.chapterIdx + 1) !== null;
  }

  private targetCursor(direction: number): PageCursor | null {
    let cursor = this.currentCursor();
    if (cursor === null) {
      return null;
    }
    const steps: number = this.spreadMode ? 2 : 1;
    for (let i: number = 0; i < steps; i++) {
      const next = this.adjacentCursor(cursor, direction);
      if (next === null) {
        // In an odd final spread, the last page is already visible on the right.
        return direction < 0 && i > 0 ? cursor : null;
      }
      cursor = next;
    }
    return cursor;
  }

  private cancelMotion(): void {
    this.refresh.stop();
    this.animationEpoch++;
    clearTimeout(this.animationTimer);
    this.animating = false;
    this.dragX = 0;
    this.previewX = 0;
    this.previewVisible = false;
    this.previewCursor = null;
  }

  private showHud(visible: boolean): void {
    this.getUIContext().animateTo(ReaderMotion.spring(this.settings.reduceMotion), () => {
      this.hudVisible = visible;
    });
  }

  private preparePreview(direction: number): boolean {
    const target = this.targetCursor(direction);
    if (target === null || !this.previewReady || !this.sceneReady(target)) {
      this.previewCursor = null;
      this.previewVisible = false;
      return false;
    }
    if (this.previewCursor === null || this.previewDirection !== direction) {
      this.previewCursor = target;
      this.previewDirection = direction;
      this.paintScene(this.previewCtx, target);
    }
    this.previewVisible = true;
    return true;
  }

  private onPanUpdate(offset: number): void {
    if (this.busy || this.navigationPending || this.animating ||
      this.panelVisible) {
      return;
    }
    this.refresh.begin(this.settings.reduceMotion);
    this.readingSession.interact();
    const direction: number = offset < 0 ? 1 : -1;
    const valid: boolean = this.preparePreview(direction);
    const width: number = px2vp(this.ctx.width);
    this.dragX = Math.max(-width, Math.min(width, offset)) * (valid ? 1 : 0.16);
    this.previewX = this.dragX + direction * width;
  }

  private onPanEnd(offset: number): void {
    this.refresh.end();
    if (this.busy || this.navigationPending || this.animating) {
      return;
    }
    if (Math.abs(offset) >= 60) {
      if (this.previewCursor !== null) {
        this.completeTurn(offset < 0 ? 1 : -1);
      } else {
        this.cancelMotion();
        this.turnPage(offset < 0 ? 1 : -1);
      }
    } else {
      this.animating = true;
      const epoch: number = ++this.animationEpoch;
      this.getUIContext().animateTo({ duration: this.settings.reduceMotion ? 0 : 200, curve: Curve.EaseOut,
        expectedFrameRateRange: this.settings.reduceMotion ? undefined : ReadingRefresh.range(),
        onFinish: () => {
          if (this.active && epoch === this.animationEpoch) {
            this.cancelMotion();
          }
        } }, () => {
        this.dragX = 0;
        this.previewX = this.previewDirection * px2vp(this.ctx.width);
      });
    }
  }

  private async turnPage(direction: number): Promise<void> {
    if (this.busy || this.navigationPending || this.animating || this.panelVisible) {
      return;
    }
    const current: PageCursor | null = this.currentCursor();
    if (current === null) {
      return;
    }
    const request: number = ++this.navigationRequest;
    const generation: number = this.generation;
    this.navigationPending = true;
    this.backgroundEpoch++;
    clearTimeout(this.indexTimer);
    try {
      const target: PageCursor | null = await PageNavigation.turn(current, direction, this.spreadMode,
        this.chapters.length, (ci: number) => this.loadForNavigation(ci, generation));
      if (!this.active || request !== this.navigationRequest || generation !== this.generation) {
        return;
      }
      if (target === null) {
        this.toast(direction > 0 ? '已经是最后一页' : '已经是第一页');
        return;
      }
      await this.ensureScene(target, generation);
      if (!this.active || request !== this.navigationRequest || generation !== this.generation) {
        return;
      }
      if (this.previewReady) {
        this.previewCursor = target;
        this.previewDirection = direction;
        this.paintScene(this.previewCtx, target);
        this.previewVisible = true;
        this.previewX = direction * px2vp(this.ctx.width);
        this.completeTurn(direction);
      } else {
        this.finishTurn(target);
      }
    } catch (e) {
      if (this.active && request === this.navigationRequest && generation === this.generation) {
        this.toast('相邻章节暂时无法打开，请再次翻页重试');
        this.cancelMotion();
      }
    } finally {
      if (this.active && request === this.navigationRequest && generation === this.generation) {
        this.navigationPending = false;
        this.scheduleBackground();
      }
    }
  }

  private completeTurn(direction: number): void {
    const target = this.previewCursor;
    if (target === null) {
      return;
    }
    this.showHud(false);
    if (this.settings.reduceMotion) {
      this.finishTurn(target);
      return;
    }
    this.animating = true;
    const epoch: number = ++this.animationEpoch;
    this.animationTimer = setTimeout(() => {
      if (!this.active || epoch !== this.animationEpoch) {
        return;
      }
      this.getUIContext().animateTo({
        duration: 250, curve: Curve.EaseOut,
        expectedFrameRateRange: ReadingRefresh.range(),
        onFinish: () => {
          if (this.active && epoch === this.animationEpoch) {
            this.finishTurn(target);
          }
        }
      }, () => {
        this.dragX = -direction * px2vp(this.ctx.width);
        this.previewX = 0;
      });
    }, 16);
  }

  private finishTurn(target: PageCursor): void {
    const pages = this.cache.get(target.chapterIdx);
    if (pages === null) {
      this.cancelMotion();
      return;
    }
    this.pages = pages;
    this.pageIdx = target.pageIdx;
    this.currentChapterIdx = target.chapterIdx;
    this.pinNeighborhood(target.chapterIdx);
    this.positionOffset = pages[target.pageIdx].startOffset;
    this.draw();
    this.cancelMotion();
    this.syncSlider();
    this.saveProgress();
    this.readingSession.interact();
    this.recordCompletion();
    this.scheduleBackground();
  }

  private onTap(xVp: number): void {
    if (this.busy || this.navigationPending || this.animating) {
      return;
    }
    this.readingSession.interact();
    const fraction: number = xVp / px2vp(this.ctx.width);
    if (fraction < 0.25) {
      this.turnPage(-1);
    } else if (fraction > 0.75) {
      this.turnPage(1);
    } else {
      this.showHud(!this.hudVisible);
    }
  }

  private syncSlider(): void {
    this.sliderValue = this.book.charCount > 1 ?
      Math.round(this.positionOffset / (this.book.charCount - 1) * 1000) : 0;
  }

  private absolutePage(cursor: PageCursor): number {
    let page: number = cursor.pageIdx + 1;
    for (let ci: number = 0; ci < cursor.chapterIdx; ci++) {
      if ((this.pageCounts[ci] ?? 0) === 0) {
        return 0;
      }
      page += this.pageCounts[ci];
    }
    return page;
  }

  private progressLabel(): string {
    const pct: number = Math.round(this.sliderValue / 10);
    if (this.sliderPreview) {
      const ci: number = this.chapterForOffset(Math.floor(this.sliderValue / 1000 * (this.book.charCount - 1)));
      return pct + '% · ' + (this.chapters[ci]?.title ?? '') + ' · 松手跳转';
    }
    const cursor = this.currentCursor();
    if (cursor !== null && this.indexedChapters === this.chapters.length) {
      const first: number = this.absolutePage(cursor);
      const right = this.spreadMode ? this.adjacentCursor(cursor, 1) : null;
      return (right !== null ? first + '–' + this.absolutePage(right) : first.toString()) +
        ' / ' + this.totalPages + ' 页 · ' + pct + '%';
    }
    return pct + '% · 第 ' + Math.max(1, this.currentChapterIdx + 1) + ' / ' + this.chapters.length + ' 章';
  }

  private onSliderChange(value: number, done: boolean): void {
    this.sliderValue = value;
    this.sliderPreview = !done;
    if (done) {
      this.navigateToOffset(Math.floor(value / 1000 * (this.book.charCount - 1)));
    }
  }

  private saveProgress(): void {
    if (!this.ready || this.book.id <= 0 || this.pages.length === 0) {
      return;
    }
    this.pendingProgressOffset = this.positionOffset;
    if (!this.progressWriteActive) {
      this.progressTask = this.flushProgress();
    }
  }

  private async flushProgress(): Promise<void> {
    if (this.progressWriteActive) {
      return;
    }
    this.progressWriteActive = true;
    try {
      while (this.pendingProgressOffset >= 0) {
        const offset: number = this.pendingProgressOffset;
        this.pendingProgressOffset = -1;
        await BookRepo.touchAndSetProgress(this.book.id, offset);
        this.book.progressCharOffset = offset;
      }
    } catch (e) {
      if (this.active) {
        this.toast('阅读进度暂未保存，将在下次翻页时重试');
      }
    } finally {
      this.progressWriteActive = false;
      if (this.pendingProgressOffset >= 0) {
        this.progressTask = this.flushProgress();
      }
    }
  }

  private pageBookmark(): Bookmark | null {
    const page = this.pages[this.pageIdx];
    if (page === undefined) {
      return null;
    }
    for (let i: number = 0; i < this.bookmarks.length; i++) {
      const bookmark = this.bookmarks[i];
      if (bookmark.charOffset >= page.startOffset &&
        (bookmark.charOffset < page.endOffset || bookmark.charOffset === this.positionOffset)) {
        return bookmark;
      }
    }
    return null;
  }

  private async backToShelf(): Promise<void> {
    if (this.leaving) {
      return;
    }
    this.leaving = true;
    this.saveProgress();
    await this.readingSession.pause().catch(() => {});
    await this.progressTask;
    await this.leaveImmersiveMode();
    router.back();
  }

  private async recordCompletion(): Promise<void> {
    if (this.completionRecorded || this.pages.length === 0) {
      return;
    }
    const cursor: PageCursor | null = this.currentCursor();
    const right: PageCursor | null = this.spreadMode && cursor !== null ? this.adjacentCursor(cursor, 1) : null;
    const lastPages: Page[] | null = right !== null ? this.cache.get(right.chapterIdx) : this.pages;
    const lastPage: Page | undefined = lastPages?.[right !== null ? right.pageIdx : this.pageIdx];
    if (lastPage === undefined || lastPage.endOffset < this.book.charCount) {
      return;
    }
    this.completionRecorded = true;
    try {
      await ReadingActivityRepo.setFinished(this.book.id, true);
    } catch (e) {
      this.completionRecorded = false;
    }
  }

  private async toggleBookmark(): Promise<void> {
    if (this.busy || this.bookmarkBusy || this.pages.length === 0) {
      return;
    }
    this.bookmarkBusy = true;
    try {
      const existing = this.pageBookmark();
      if (existing !== null) {
        await BookmarkRepo.remove(existing.id);
        this.toast('已移除书签');
      } else {
        const excerpt: string = await ImportService.readExcerpt(this.book, this.positionOffset, 100);
        await BookmarkRepo.add(this.book.id, this.positionOffset, excerpt.replace(/\s+/g, ' ').trim());
        this.toast('已添加书签');
      }
      this.bookmarks = await BookmarkRepo.listByBook(this.book.id);
    } catch (e) {
      this.toast('书签未能保存，请重试');
    } finally {
      this.bookmarkBusy = false;
    }
  }

  private confirmRemoveBookmark(bookmark: Bookmark): void {
    AlertDialog.show({
      title: '删除书签？',
      message: '只移除这条书签，不影响图书和阅读进度。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除', fontColor: $r('app.color.destructive'),
        action: () => this.removeBookmark(bookmark)
      }
    });
  }

  private async removeBookmark(bookmark: Bookmark): Promise<void> {
    try {
      await BookmarkRepo.remove(bookmark.id);
      this.bookmarks = await BookmarkRepo.listByBook(this.book.id);
    } catch (e) {
      this.toast('未能删除书签，请重试');
    }
  }

  private palette(): ReadingPalette {
    return ThemeManager.resolve(this.settings.theme, this.isDark, this.preferences.appearance);
  }

  private chromeMode(): ThemeColorMode {
    return ThemeManager.chromeDark(this.settings.theme, this.isDark, this.preferences.appearance) ?
      ThemeColorMode.DARK : ThemeColorMode.LIGHT;
  }

  private paintPage(ctx: CanvasRenderingContext2D, cursor: PageCursor, originX: number,
    width: number, palette: ReadingPalette): void {
    const pages = this.cache.get(cursor.chapterIdx);
    if (pages === null || cursor.pageIdx >= pages.length) {
      return;
    }
    const page = pages[cursor.pageIdx];
    const x: number = originX + vp2px(this.spreadMode ? 32 : 24);
    ctx.textBaseline = 'top';
    ctx.fillStyle = palette.text;
    ctx.font = fp2px(this.settings.fontSize) + 'px ' + ReadingFonts.family(this.settings);
    for (let i: number = 0; i < page.lines.length; i++) {
      const line = page.lines[i];
      const link: ContentsLink | undefined = this.chapterLinks.get(cursor.chapterIdx)?.find((candidate: ContentsLink) =>
        candidate.start < line.endOffset && candidate.end > line.startOffset);
      ctx.fillStyle = link === undefined ? palette.text : this.chromeMode() === ThemeColorMode.DARK ? '#78B7FF' : '#1764AD';
      ctx.fillText(line.text, x, line.y);
      if (link !== undefined && ctx === this.ctx) {
        this.paintedLinks.push(new ContentsHit(x, line.y, Math.min(ctx.measureText(line.text).width + vp2px(12),
          width - vp2px(this.spreadMode ? 64 : 48)), fp2px(this.settings.fontSize) * this.settings.lineHeight, link));
      }
    }
    ctx.fillStyle = palette.meta;
    ctx.font = fp2px(12) + 'px sans-serif';
    let title: string = this.chapters[cursor.chapterIdx].title;
    const titleWidth: number = width - vp2px(64);
    while (title.length > 0 && ctx.measureText(title + '…').width > titleWidth) {
      title = title.substring(0, title.length - 1);
    }
    if (title !== this.chapters[cursor.chapterIdx].title) {
      title += '…';
    }
    ctx.fillText(title, x, vp2px(24 + this.safeTop));
    const label: string = '本章 ' + (cursor.pageIdx + 1) + ' / ' + pages.length;
    ctx.font = fp2px(11) + 'px "JetBrains Mono"';
    const labelWidth: number = ctx.measureText(label).width;
    ctx.fillText(label, originX + (width - labelWidth) / 2, ctx.height - vp2px(28 + this.safeBottom));
  }

  private paintScene(ctx: CanvasRenderingContext2D, cursor: PageCursor | null): void {
    const palette = this.palette();
    ctx.clearRect(0, 0, ctx.width, ctx.height);
    ctx.fillStyle = palette.bg;
    ctx.globalAlpha = this.settings.backgroundPath ? 1 - this.settings.backgroundOpacity : 1;
    ctx.fillRect(0, 0, ctx.width, ctx.height);
    ctx.globalAlpha = 1;
    if (cursor === null) {
      return;
    }
    const gutter: number = this.spreadMode ? vp2px(READER_SPREAD_GUTTER) : 0;
    const pageWidth: number = this.spreadMode ? (ctx.width - gutter) / 2 :
      Math.min(ctx.width, vp2px(READER_SINGLE_MAX_WIDTH));
    this.paintPage(ctx, cursor, this.spreadMode ? 0 : (ctx.width - pageWidth) / 2, pageWidth, palette);
    if (this.spreadMode) {
      const right = this.adjacentCursor(cursor, 1);
      if (right !== null) {
        this.paintPage(ctx, right, pageWidth + gutter, pageWidth, palette);
      }
      ctx.fillStyle = palette.meta;
      ctx.globalAlpha = 0.18;
      ctx.fillRect(pageWidth + gutter / 2, vp2px(28), 1, ctx.height - vp2px(56));
      ctx.globalAlpha = 1;
    }
  }

  private draw(): void {
    // Keep the last complete frame until replacement pagination is ready.
    if (this.busy && this.pages.length > 0) {
      return;
    }
    if (this.canvasReady) {
      this.paintedLinks = [];
      this.paintScene(this.ctx, this.currentCursor());
      this.visibleContentsLinks = this.paintedLinks.slice();
    }
  }

  private canvasDescription(): string {
    const cursor = this.currentCursor();
    if (cursor === null) {
      return '正在准备正文';
    }
    const page = this.pages[this.pageIdx];
    let body: string = page.lines.map((line) => line.text).join('\n');
    const right = this.spreadMode ? this.adjacentCursor(cursor, 1) : null;
    if (right !== null) {
      const pages = this.cache.get(right.chapterIdx);
      if (pages !== null) {
        body += '\n' + pages[right.pageIdx].lines.map((line) => line.text).join('\n');
      }
    }
    return (this.spreadMode ? '双页阅读。' : '单页阅读。') + this.chapters[cursor.chapterIdx].title + '。' + body;
  }

  private setLayout(mode: string): void {
    if (mode === this.settings.layoutMode) {
      return;
    }
    this.settings.layoutMode = mode;
    this.spreadMode = this.wideWindow && mode !== 'single';
    this.scheduleLayout();
  }

  private onBreakpoint(breakpoint: string): void {
    this.wideWindow = breakpoint !== 'xs';
    const next: boolean = this.wideWindow && this.settings.layoutMode !== 'single';
    if (next !== this.spreadMode) {
      this.spreadMode = next;
      this.scheduleLayout();
    }
  }

  private adjustFont(delta: number): void {
    const next: number = Math.max(17, Math.min(26, this.settings.fontSize + delta));
    if (next !== this.settings.fontSize) {
      this.settings.fontSize = next;
      this.scheduleLayout(80);
    }
  }

  private adjustLineHeight(delta: number): void {
    const next: number = Math.max(1.4, Math.min(2,
      Math.round((this.settings.lineHeight + delta) * 100) / 100));
    if (next !== this.settings.lineHeight) {
      this.settings.lineHeight = next;
      this.scheduleLayout(80);
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }

  @Monitor('settings.fontFamily', 'settings.fontChoice')
  fontChanged(): void { this.scheduleLayout(80); }
  @Monitor('settings.backgroundPath', 'settings.backgroundOpacity')
  backgroundChanged(): void { this.draw(); }

  private openPanel(kind: string): void {
    this.readingSession.pause().catch(() => {});
    this.panelKind = kind;
    this.panelVisible = true;
  }

  private async followContentsLink(offset: number): Promise<void> {
    if (this.busy || this.animating || this.navigationPending || this.panelVisible) { return; }
    this.showHud(false);
    await this.navigateToOffset(offset);
  }

  @Builder
  contentsPanel() {
    ReadingContentsPanel({
      book: this.book, chapters: this.chapters, bookmarks: this.bookmarks,
      current: this.currentChapterIdx, pending: this.outlineBusy,
      onOpen: (offset: number) => this.openOutlinePosition(offset),
      onAddBookmark: () => this.toggleBookmark(),
      onDeleteBookmark: (bookmark: Bookmark) => this.confirmRemoveBookmark(bookmark),
      onClose: () => { this.panelVisible = false; }
    })
  }

  private async openOutlinePosition(offset: number): Promise<void> {
    if (this.outlineBusy || this.busy) { return; }
    this.outlineBusy = true;
    try {
      await this.navigateToOffset(offset);
      if (this.active && !this.busy && this.errorMessage.length === 0) {
        this.panelVisible = false;
      } else if (this.errorMessage.length > 0) {
        this.toast(this.errorMessage);
      }
    } finally { this.outlineBusy = false; }
  }

  @Builder
  panelBuilder() {
    WithTheme({ colorMode: this.chromeMode() }) {
      this.panelContent()
    }
  }

  @Builder
  panelContent() {
    if (this.panelKind === 'settings') {
      ReadingSettingsPanel({
        palette: this.palette(),
        settings: this.settings,
        wideWindow: this.wideWindow,
        onFont: (delta: number) => this.adjustFont(delta),
        onLineHeight: (delta: number) => this.adjustLineHeight(delta),
        onTheme: (theme: string) => {
          this.settings.theme = theme;
          this.draw();
        },
        onLayoutMode: (mode: string) => this.setLayout(mode),
        onReduceMotion: (value: boolean) => { this.settings.reduceMotion = value; },
        onClose: () => { this.panelVisible = false; }
      })
    } else {
      this.contentsPanel()
    }
  }

  @Builder
  stateOverlay() {
    Column({ space: Spacing.BASE }) {
      if (this.errorMessage.length > 0) {
      Text('暂时无法阅读')
          .fontSize(TypeScale.TITLE).fontWeight(700).fontColor($r('app.color.label_primary'))
        Text(this.errorMessage)
          .fontSize(TypeScale.BODY).fontColor($r('app.color.label_secondary'))
          .textAlign(TextAlign.Center).constraintSize({ maxWidth: 340 })
        Row({ space: 16 }) {
          Text('返回书架').height(48).padding({ left: 24, right: 24 })
            .fontColor($r('app.color.primary')).textAlign(TextAlign.Center)
            .onClick(() => this.backToShelf())
          Text('重试').height(48).padding({ left: 24, right: 24 })
            .fontColor($r('app.color.on_primary')).textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.primary')).borderRadius(24)
            .onClick(() => {
              if (this.ready) {
                this.scheduleLayout();
              } else {
                this.init();
              }
            })
        }
      } else {
        LoadingProgress().width(32).height(32)
        Text(this.ready ? '正在排版…' : '正在打开图书…')
          .fontSize(TypeScale.SUBHEAD).fontColor($r('app.color.label_secondary'))
      }
    }
    .width('100%').height('100%').padding(32).justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  readerPage() {
    GridRow({ columns: 12, breakpoints: { value: ['1000vp'], reference: BreakpointsReference.WindowSize } }) {
      GridCol({ span: 12 }) {
        Row() {
          Stack({ alignContent: Alignment.TopStart }) {
            if (this.settings.backgroundPath) {
              Image('file://' + this.settings.backgroundPath).width('100%').height('100%').objectFit(ImageFit.Cover)
                .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
            }
            Canvas(this.previewCtx)
              .width('100%').height('100%')
              .onReady(() => { this.previewReady = true; })
              .translate({ x: this.previewX })
              .opacity(this.previewVisible ? 1 : 0)
              .hitTestBehavior(HitTestMode.None)
              .accessibilityLevel('no')

            Canvas(this.ctx)
              .id('reader_canvas')
              .width('100%').height('100%')
              .opacity(this.paperOpacity)
              .translate({ x: this.dragX })
              .onReady(() => {
                this.canvasReady = true;
                this.scheduleLayout();
              })
              .onAreaChange((oldArea: Area, newArea: Area) => {
                if (oldArea.width !== newArea.width || oldArea.height !== newArea.height) {
                  this.scheduleLayout();
                }
              })
              .accessibilityText(this.canvasDescription())
              .onClick((event: ClickEvent) => this.onTap(event.x))
              .gesture(
                PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
                  .onActionUpdate((event: GestureEvent) => this.onPanUpdate(event.offsetX))
                  .onActionEnd((event: GestureEvent) => this.onPanEnd(event.offsetX))
                  .onActionCancel(() => this.cancelMotion())
              )

            if (!this.busy && !this.panelVisible) {
              ForEach(this.visibleContentsLinks, (link: ContentsHit, index: number) => {
                Button({ type: ButtonType.Normal }) { Text('').accessibilityLevel('no') }
                  .id('epub_contents_link_' + index).position({ x: px2vp(link.x), y: px2vp(link.y) })
                  .width(px2vp(link.width)).height(px2vp(link.height)).padding(0)
                  .backgroundColor(Color.Transparent).borderRadius(4)
                  .enabled(!this.animating).translate({ x: this.dragX })
                  .accessibilityText('跳转到：' + link.label)
                  .onClick(() => this.followContentsLink(link.target))
                  .gesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
                    .onActionUpdate((event: GestureEvent) => this.onPanUpdate(event.offsetX))
                    .onActionEnd((event: GestureEvent) => this.onPanEnd(event.offsetX))
                    .onActionCancel(() => this.cancelMotion()))
              }, (link: ContentsHit) => link.target + ':' + link.x + ':' + link.y)
            }

            if (this.hudVisible && this.ready) {
              Column() {
                HudTopBar({
                  palette: this.palette(),
                  title: this.book.title,
                  bookmarked: this.pageBookmark() !== null,
                  onBack: () => this.backToShelf(),
                  onBookmark: () => this.toggleBookmark()
                })
                .transition(ReaderMotion.reveal(this.settings.reduceMotion, -16))
                Blank().hitTestBehavior(HitTestMode.None)
                HudBottomBar({
                  palette: this.palette(),
                  sliderValue: this.sliderValue, progressLabel: this.progressLabel(),
                  onSlider: (value: number, done: boolean) => this.onSliderChange(value, done),
                  onToc: () => this.openPanel('contents'),
                  onSettings: () => this.openPanel('settings')
                })
                .transition(ReaderMotion.reveal(this.settings.reduceMotion, 16))
              }
              .width('100%').height('100%')
              .padding({ top: this.safeTop, bottom: this.safeBottom })
              .hitTestBehavior(HitTestMode.Transparent)
            }

            if (this.navigationPending && !this.busy) {
              Column() {
                Blank()
                LoadingProgress().width(24).height(24)
                  .accessibilityText('正在准备下一页')
              }
              .width('100%').height('100%')
              .padding({ bottom: 44 + this.safeBottom })
              .hitTestBehavior(HitTestMode.None)
            }

            if ((this.busy && this.pages.length === 0) || this.errorMessage.length > 0) {
              this.stateOverlay()
            }
          }
          .width('100%').height('100%')
          .constraintSize({ maxWidth: this.wideWindow ? READER_SPREAD_MAX_WIDTH : READER_SINGLE_MAX_WIDTH })
          .clip(true)
          .bindSheet($$this.panelVisible, this.panelBuilder(), {
            height: SheetSize.LARGE, dragBar: true, showClose: false,
            preferType: this.wideWindow ? SheetType.CENTER : SheetType.BOTTOM,
            width: this.wideWindow ? 540 : '100%', backgroundColor: this.palette().chrome,
            onDisappear: () => this.resumeReading()
          })
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor(this.palette().bg)
      }
      .height('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(this.palette().bg)
    .onBreakpointChange((breakpoint: string) => this.onBreakpoint(breakpoint))
  }

  build() {
    WithTheme({ colorMode: this.chromeMode() }) {
      this.readerPage()
    }
  }
}
