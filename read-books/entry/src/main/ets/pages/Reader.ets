import { router, mediaquery } from '@kit.ArkUI';
import { Book, Chapter, Page } from '../model/Models';
import { ReadingSettings } from '../model/ReadingSettings';
import { BookRepo } from '../data/BookRepo';
import { ChapterRepo } from '../data/ChapterRepo';
import { ImportService } from '../reader/ImportService';
import { Paginator, PageCache, Measurer, LayoutConstraints } from '../reader/Paginator';
import { ThemeManager, ReadingPalette } from '../theme/ThemeManager';
import { HudTopBar, HudBottomBar } from '../components/HudBar';
import { Spacing, TypeScale, Radius, TouchTarget } from '../theme/tokens';

/** Canvas 文本测量器（注入引擎，含字符宽度缓存） */
class CanvasMeasurer implements Measurer {
  private ctx: CanvasRenderingContext2D;
  private cache: Map<string, number> = new Map<string, number>();

  constructor(ctx: CanvasRenderingContext2D) {
    this.ctx = ctx;
  }

  measure(ch: string): number {
    const hit = this.cache.get(ch);
    if (hit !== undefined) {
      return hit;
    }
    const w: number = this.ctx.measureText(ch).width;
    this.cache.set(ch, w);
    return w;
  }

  clear(): void {
    this.cache.clear();
  }
}

/**
 * 阅读器 —— docs/DESIGN.md §4.3 / §5
 * 热区：左 25% 上一页 · 右 25% 下一页 · 中央 50% 呼出 HUD
 * 进度锚点：字符偏移（改字号不丢位置）
 */
@Entry
@ComponentV2
struct Reader {
  @Local book: Book = new Book();
  @Local chapters: Chapter[] = [];
  @Local text: string = '';
  @Local pages: Page[] = [];
  @Local pageIdx: number = 0;
  @Local hudVisible: boolean = false;
  @Local showToc: boolean = false;
  @Local showSettings: boolean = false;
  @Local isDark: boolean = false;
  @Local ready: boolean = false;
  @Local sliderValue: number = 0;

  settings: ReadingSettings = ReadingSettings.load();
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private measurer: CanvasMeasurer | null = null;
  private cache: PageCache = new PageCache();
  private currentChapterIdx: number = -1;
  private darkListener: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    this.init();
    this.darkListener = mediaquery.matchMediaSync('(prefers-color-scheme: dark)');
    this.isDark = this.darkListener.matches;
    this.darkListener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.isDark = result.matches;
      this.draw();
    });
  }

  aboutToDisappear(): void {
    if (this.darkListener !== null) {
      this.darkListener.off('change');
    }
    this.saveProgress();
  }

  private async init(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    const bookId: number = params !== undefined ? (params['bookId'] as number) : 0;
    const b = await BookRepo.getById(bookId);
    if (b === null) {
      router.back();
      return;
    }
    this.book = b;
    this.chapters = await ChapterRepo.listByBook(bookId);
    this.text = await ImportService.readTextFile(b.filePath);
    this.ready = true;
    // Canvas onReady 后执行 restoreProgress；此处兜底直接尝试
    this.restoreIfPossible();
  }

  private restoreIfPossible(): void {
    if (this.measurer !== null && this.ready && this.chapters.length > 0) {
      this.restoreProgress();
    }
  }

  private restoreProgress(): void {
    const off: number = Math.max(0, Math.min(this.book.progressCharOffset, this.text.length - 1));
    const ci: number = this.chapterForOffset(off);
    this.ensurePagesFor(ci, off);
    this.draw();
    this.syncSlider();
  }

  private chapterForOffset(off: number): number {
    for (let i = 0; i < this.chapters.length; i++) {
      if (off < this.chapters[i].endOffset) {
        return i;
      }
    }
    return this.chapters.length - 1;
  }

  private constraints(): LayoutConstraints {
    const fontPx: number = vp2px(this.settings.fontSize);
    const lc: LayoutConstraints = {
      widthPx: this.ctx.width,
      heightPx: this.ctx.height,
      padLeftPx: vp2px(20),
      padRightPx: vp2px(20),
      padTopPx: vp2px(56),
      padBottomPx: vp2px(48),
      fontSizePx: fontPx,
      lineHeightRatio: this.settings.lineHeight
    };
    return lc;
  }

  private ensurePagesFor(chapterIdx: number, anchorOffset: number): void {
    if (chapterIdx < 0 || chapterIdx >= this.chapters.length || this.measurer === null) {
      return;
    }
    let pages = this.cache.get(chapterIdx);
    if (pages === null) {
      const ch = this.chapters[chapterIdx];
      pages = Paginator.paginateChapter(this.text, ch, this.constraints(), this.measurer);
      this.cache.put(chapterIdx, pages);
    }
    this.pages = pages;
    this.currentChapterIdx = chapterIdx;
    this.pageIdx = Paginator.locateByOffset(pages, anchorOffset);
  }

  private currentOffset(): number {
    if (this.pageIdx >= 0 && this.pageIdx < this.pages.length) {
      return this.pages[this.pageIdx].startOffset;
    }
    return this.book.progressCharOffset;
  }

  private syncSlider(): void {
    if (this.text.length <= 0) {
      this.sliderValue = 0;
      return;
    }
    this.sliderValue = Math.floor(this.currentOffset() / this.text.length * 1000);
  }

  private progressLabel(): string {
    if (this.text.length <= 0) {
      return '';
    }
    const pct: number = Math.floor(this.currentOffset() / this.text.length * 100);
    const ci: number = this.currentChapterIdx;
    if (ci >= 0 && ci < this.chapters.length) {
      return pct + '% · 第 ' + (ci + 1) + ' / ' + this.chapters.length + ' 章';
    }
    return pct + '%';
  }

  private turnPage(delta: number): void {
    if (delta > 0) {
      if (this.pageIdx < this.pages.length - 1) {
        this.pageIdx += 1;
      } else if (this.currentChapterIdx < this.chapters.length - 1) {
        const next = this.chapters[this.currentChapterIdx + 1];
        this.ensurePagesFor(this.currentChapterIdx + 1, next.startOffset);
        this.pageIdx = 0;
      } else {
        return;
      }
    } else {
      if (this.pageIdx > 0) {
        this.pageIdx -= 1;
      } else if (this.currentChapterIdx > 0) {
        const prev = this.chapters[this.currentChapterIdx - 1];
        this.ensurePagesFor(this.currentChapterIdx - 1, prev.startOffset);
        this.pageIdx = this.pages.length - 1;
      } else {
        return;
      }
    }
    if (this.hudVisible) {
      this.hudVisible = false;
    }
    this.draw();
    this.syncSlider();
    this.saveProgress();
  }

  private jumpToOffset(off: number): void {
    if (this.text.length <= 0) {
      return;
    }
    const clamped: number = Math.max(0, Math.min(off, this.text.length - 1));
    const ci: number = this.chapterForOffset(clamped);
    this.ensurePagesFor(ci, clamped);
    this.draw();
    this.syncSlider();
    this.saveProgress();
  }

  private onSliderChange(value: number, done: boolean): void {
    if (!done) {
      return;
    }
    const target: number = Math.floor(value / 1000 * this.text.length);
    this.jumpToOffset(target);
  }

  private async saveProgress(): Promise<void> {
    if (this.book.id > 0) {
      await BookRepo.touchAndSetProgress(this.book.id, this.currentOffset());
    }
  }

  private palette(): ReadingPalette {
    return ThemeManager.resolve(this.settings.theme, this.isDark);
  }

  private onTap(xVp: number, yVp: number): void {
    if (this.settings.pageMode === 'slide') {
      this.hudVisible = !this.hudVisible;
      return;
    }
    const wVp: number = px2vp(this.ctx.width);
    if (xVp < wVp * 0.25) {
      this.turnPage(-1);
    } else if (xVp > wVp * 0.75) {
      this.turnPage(1);
    } else {
      this.hudVisible = !this.hudVisible;
    }
  }

  private onCanvasReady(): void {
    this.measurer = new CanvasMeasurer(this.ctx);
    this.applyFont();
    this.restoreIfPossible();
  }

  private applyFont(): void {
    const fontPx: number = vp2px(this.settings.fontSize);
    this.ctx.font = fontPx + 'px sans-serif';
  }

  private draw(): void {
    const p: ReadingPalette = this.palette();
    const ctx: CanvasRenderingContext2D = this.ctx;
    const w: number = ctx.width;
    const h: number = ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    ctx.fillStyle = p.bg;
    ctx.fillRect(0, 0, w, h);
    if (this.pages.length === 0 || this.pageIdx >= this.pages.length) {
      return;
    }
    ctx.textBaseline = 'top';
    ctx.fillStyle = p.text;
    this.applyFont();
    const page: Page = this.pages[this.pageIdx];
    const x: number = vp2px(20);
    for (let i = 0; i < page.lines.length; i++) {
      ctx.fillText(page.lines[i].text, x, page.lines[i].y);
    }
    // 页眉：章节名
    ctx.fillStyle = p.meta;
    ctx.font = vp2px(12) + 'px sans-serif';
    if (this.currentChapterIdx >= 0 && this.currentChapterIdx < this.chapters.length) {
      const title: string = this.chapters[this.currentChapterIdx].title;
      if (title.length > 20) {
        ctx.fillText(title.substring(0, 20) + '…', x, vp2px(24));
      } else {
        ctx.fillText(title, x, vp2px(24));
      }
    }
    // 页脚：本章页码 · 全书进度
    const pct: number = this.text.length > 0 ? Math.floor(this.currentOffset() / this.text.length * 100) : 0;
    const label: string = (this.pageIdx + 1) + ' / ' + this.pages.length + ' · ' + pct + '%';
    const tw: number = ctx.measureText(label).width;
    ctx.fillText(label, (w - tw) / 2, h - vp2px(28));
  }

  /** 设置变更后重排：清缓存、按字符锚点回位 —— docs/DESIGN.md §5.6 */
  private relayoutKeepPosition(): void {
    if (this.measurer === null) {
      return;
    }
    const anchor: number = this.currentOffset();
    this.cache.clear();
    this.measurer.clear();
    this.applyFont();
    const ci: number = this.chapterForOffset(anchor);
    this.ensurePagesFor(ci, anchor);
    this.draw();
    this.syncSlider();
  }

  private adjustFont(delta: number): void {
    const nv: number = Math.max(17, Math.min(26, this.settings.fontSize + delta));
    if (nv === this.settings.fontSize) {
      return;
    }
    this.settings.fontSize = nv;
    this.relayoutKeepPosition();
  }

  private adjustLineHeight(delta: number): void {
    const nv: number = Math.max(1.4, Math.min(2.0, Math.round((this.settings.lineHeight + delta) * 100) / 100));
    if (nv === this.settings.lineHeight) {
      return;
    }
    this.settings.lineHeight = nv;
    this.relayoutKeepPosition();
  }

  private setTheme(theme: string): void {
    this.settings.theme = theme;
    this.draw();
  }

  private setMode(mode: string): void {
    this.settings.pageMode = mode;
  }

  @Builder
  tocBuilder() {
    Column() {
      Text('目录')
        .fontSize(TypeScale.HEADLINE)
        .fontWeight(600)
        .fontColor($r('app.color.label_primary'))
        .width('100%')
        .padding({ left: Spacing.BASE, right: Spacing.BASE, top: Spacing.BASE, bottom: Spacing.S })
      List() {
        ForEach(this.chapters, (c: Chapter) => {
          ListItem() {
            Text(c.title)
              .fontSize(TypeScale.BODY)
              .fontColor(c.idx === this.currentChapterIdx
                ? $r('app.color.primary')
                : $r('app.color.label_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ top: Spacing.M, bottom: Spacing.M, left: Spacing.BASE, right: Spacing.BASE })
              .width('100%')
              .onClick(() => {
                this.showToc = false;
                this.jumpToOffset(c.startOffset);
              })
          }
        }, (c: Chapter) => c.idx.toString())
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 1, color: $r('app.color.separator'), startMargin: Spacing.BASE, endMargin: Spacing.BASE })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  settingsBuilder() {
    Column({ space: Spacing.L }) {
      Text('阅读设置')
        .fontSize(TypeScale.HEADLINE)
        .fontWeight(600)
        .fontColor($r('app.color.label_primary'))
        .width('100%')

      // 字号
      Row() {
        Text('字号')
          .fontSize(TypeScale.BODY)
          .fontColor($r('app.color.label_primary'))
        Blank()
        Text('A−')
          .fontSize(TypeScale.BODY)
          .fontColor($r('app.color.primary'))
          .width(TouchTarget.MIN)
          .height(TouchTarget.MIN)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.adjustFont(-1);
          })
        Text(this.settings.fontSize.toFixed(0))
          .fontSize(TypeScale.BODY)
          .fontColor($r('app.color.label_primary'))
          .width(48)
          .textAlign(TextAlign.Center)
        Text('A+')
          .fontSize(TypeScale.BODY)
          .fontWeight(600)
          .fontColor($r('app.color.primary'))
          .width(TouchTarget.MIN)
          .height(TouchTarget.MIN)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.adjustFont(1);
          })
      }
      .width('100%')

      // 行距
      Row() {
        Text('行距')
          .fontSize(TypeScale.BODY)
          .fontColor($r('app.color.label_primary'))
        Blank()
        Text('−')
          .fontSize(TypeScale.HEADLINE)
          .fontColor($r('app.color.primary'))
          .width(TouchTarget.MIN)
          .height(TouchTarget.MIN)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.adjustLineHeight(-0.05);
          })
        Text(this.settings.lineHeight.toFixed(2))
          .fontSize(TypeScale.BODY)
          .fontColor($r('app.color.label_primary'))
          .width(48)
          .textAlign(TextAlign.Center)
        Text('+')
          .fontSize(TypeScale.HEADLINE)
          .fontColor($r('app.color.primary'))
          .width(TouchTarget.MIN)
          .height(TouchTarget.MIN)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.adjustLineHeight(0.05);
          })
      }
      .width('100%')

      // 阅读主题
      Column({ space: Spacing.S }) {
        Text('主题')
          .fontSize(TypeScale.BODY)
          .fontColor($r('app.color.label_primary'))
          .width('100%')
        Row({ space: Spacing.M }) {
          this.themeChip('system', '跟随', '#F2F2F7')
          this.themeChip('paper', '纸白', '#F7F2E7')
          this.themeChip('white', '纯白', '#FFFFFF')
          this.themeChip('night', '夜间', '#000000')
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')

      // 翻页模式
      Column({ space: Spacing.S }) {
        Text('翻页')
          .fontSize(TypeScale.BODY)
          .fontColor($r('app.color.label_primary'))
          .width('100%')
        Row({ space: Spacing.S }) {
          this.modeChip('slide', '滑动')
          this.modeChip('tap', '点按')
          this.modeChip('both', '两者')
        }
        .width('100%')
      }
      .width('100%')
    }
    .width('100%')
    .padding(Spacing.L)
    .backgroundColor($r('app.color.background'))
    .borderRadius({ topLeft: Radius.XL, topRight: Radius.XL })
  }

  @Builder
  themeChip(theme: string, label: string, color: string) {
    Column({ space: Spacing.XS }) {
      Column()
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(color)
        .border({
          width: this.settings.theme === theme ? 2 : 1,
          color: this.settings.theme === theme ? $r('app.color.primary') : $r('app.color.separator')
        })
      Text(label)
        .fontSize(TypeScale.CAPTION)
        .fontColor(this.settings.theme === theme
          ? $r('app.color.primary')
          : $r('app.color.label_secondary'))
    }
    .onClick(() => {
      this.setTheme(theme);
    })
  }

  @Builder
  modeChip(mode: string, label: string) {
    Text(label)
      .fontSize(TypeScale.SUBHEAD)
      .fontColor(this.settings.pageMode === mode
        ? $r('app.color.on_primary')
        : $r('app.color.label_primary'))
      .height(36)
      .padding({ left: Spacing.BASE, right: Spacing.BASE })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.settings.pageMode === mode
        ? $r('app.color.primary')
        : $r('app.color.surface'))
      .borderRadius(18)
      .border({
        width: 1,
        color: this.settings.pageMode === mode ? $r('app.color.primary') : $r('app.color.separator')
      })
      .onClick(() => {
        this.setMode(mode);
      })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.onCanvasReady();
        })
        .onClick((e: ClickEvent) => {
          this.onTap(e.x, e.y);
        })
        .gesture(
          PanGesture({ fingers: 1, distance: 8 })
            .onActionEnd((e: GestureEvent) => {
              if (this.settings.pageMode === 'tap') {
                return;
              }
              if (e.offsetX < -60) {
                this.turnPage(1);
              } else if (e.offsetX > 60) {
                this.turnPage(-1);
              }
            })
        )

      Column() {
        if (this.hudVisible) {
          HudTopBar({
            title: this.book.title,
            onBack: () => {
              this.saveProgress();
              router.back();
            }
          })
        }
        Blank()
        if (this.hudVisible) {
          HudBottomBar({
            sliderValue: this.sliderValue,
            progressLabel: this.progressLabel(),
            onSlider: (value: number, done: boolean) => {
              this.onSliderChange(value, done);
            },
            onToc: () => {
              this.showToc = true;
            },
            onSettings: () => {
              this.showSettings = true;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().bg)
    .bindSheet($$this.showToc, this.tocBuilder(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: false
    })
    .bindSheet($$this.showSettings, this.settingsBuilder(), {
      height: 460,
      dragBar: true,
      showClose: false
    })
  }
}
