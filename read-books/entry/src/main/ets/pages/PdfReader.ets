import { router, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { PdfView, pdfService, pdfViewManager } from '@kit.PDFKit';
import { Book, Bookmark } from '../model/Models';
import { ReadingSettings } from '../model/ReadingSettings';
import { BookRepo } from '../data/BookRepo';
import { BookmarkRepo } from '../data/BookmarkRepo';
import { ReadingActivityRepo } from '../data/ReadingActivityRepo';
import { ReadingSession } from '../reader/ReadingSession';
import { WindowMode } from '../utils/WindowMode';
import { HudTopBar } from '../components/HudBar';
import { IconButton } from '../components/IconButton';
import { ReadingChoice } from '../components/ReadingSettingsPanel';
import { ReaderMotion, LightFeedback } from '../theme/ReaderMotion';

/** Native PDF rendering, text selection and pinch zoom; app chrome shares the book reader style. */
@Entry
@ComponentV2
struct PdfReader {
  @Local book: Book = new Book();
  @Local pageIndex: number = 0;
  @Local pageCount: number = 0;
  @Local sliderValue: number = 0;
  @Local wideWindow: boolean = false;
  @Local spreadMode: boolean = false;
  @Local continuous: boolean = false;
  @Local fitWidth: boolean = false;
  @Local zoom: number = 1;
  @Local busy: boolean = true;
  @Local errorMessage: string = '';
  @Local controlsVisible: boolean = true;
  @Local panelVisible: boolean = false;
  @Local panelKind: string = 'bookmarks';
  @Local bookmarks: Bookmark[] = [];
  @Local bookmarkBusy: boolean = false;
  @Local pageInput: string = '';
  @Local searchText: string = '';
  @Local searchCount: number = 0;
  @Local searchIndex: number = 0;
  @Local searchBusy: boolean = false;
  @Local safeTop: number = 0;
  @Local safeBottom: number = 0;
  @Local completionRecorded: boolean = false;

  private settings: ReadingSettings = ReadingSettings.load();
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  private session: ReadingSession = new ReadingSession();
  private readerWindow: window.Window | null = null;
  private active: boolean = true;
  private foreground: boolean = true;
  private loaded: boolean = false;
  private loading: boolean = false;
  private leaving: boolean = false;
  private heartbeat: number = -1;
  private pendingProgress: number = -1;
  private progressTask: Promise<void> = Promise.resolve();
  private writingProgress: boolean = false;
  private searchRequest: number = 0;
  private windowEvent = (event: window.WindowEventType): void => {
    if (event === window.WindowEventType.WINDOW_HIDDEN) {
      this.setForeground(false);
    } else if (event === window.WindowEventType.WINDOW_SHOWN) {
      this.setForeground(true);
    }
  };

  aboutToAppear(): void {
    this.active = true;
    this.heartbeat = setInterval(() => {
      this.saveProgress();
      this.session.flush().catch(() => {});
    }, 30000);
  }

  onPageShow(): void { this.setForeground(true); }
  pageTransition() {
    PageTransitionEnter(ReaderMotion.pageEnter(this.settings.reduceMotion))
      .opacity(this.settings.reduceMotion ? 1 : 0)
      .translate({ y: this.settings.reduceMotion ? 0 : 20 })
      .scale({ x: this.settings.reduceMotion ? 1 : 0.985, y: this.settings.reduceMotion ? 1 : 0.985 })
      .onEnter((_type: RouteType, progress: number) => {
        if (progress >= 1 && this.active && !this.leaving && this.readerWindow === null) {
          this.enterImmersiveMode();
        }
      })
    PageTransitionExit(ReaderMotion.pageExit(this.settings.reduceMotion))
      .opacity(this.settings.reduceMotion ? 1 : 0)
      .translate({ y: this.settings.reduceMotion ? 0 : 16 })
  }
  onPageHide(): void { this.setForeground(false); }

  aboutToDisappear(): void {
    this.setForeground(false);
    this.active = false;
    this.searchRequest++;
    clearInterval(this.heartbeat);
    this.leaveImmersiveMode();
    // A load still in flight releases its own controller after resolving.
    if (!this.loading) {
      this.controller.releaseDocument();
      this.loaded = false;
    }
  }

  onBackPress(): boolean {
    if (this.panelVisible) {
      this.panelVisible = false;
    } else {
      this.backToShelf();
    }
    return true;
  }

  private setForeground(visible: boolean): void {
    this.foreground = visible;
    if (visible) {
      this.resumeReading();
    } else {
      this.session.pause().catch(() => {});
      this.saveProgress();
    }
  }

  private resumeReading(): void {
    if (this.active && this.foreground && this.loaded && !this.busy && !this.panelVisible) {
      this.session.resume();
    }
  }

  private async enterImmersiveMode(): Promise<void> {
    try {
      const win = await window.getLastWindow(getContext(this) as common.UIAbilityContext);
      if (!this.active) { return; }
      this.readerWindow = win;
      const cutout = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      this.safeTop = px2vp(cutout.topRect.height);
      this.safeBottom = px2vp(cutout.bottomRect.height);
      win.on('windowEvent', this.windowEvent);
      await WindowMode.setReaderMode(win, true);
    } catch (e) {}
  }

  private async leaveImmersiveMode(): Promise<void> {
    const win = this.readerWindow;
    this.readerWindow = null;
    if (win === null) { return; }
    try {
      win.off('windowEvent', this.windowEvent);
      await WindowMode.setReaderMode(win, false);
    } catch (e) {}
  }

  private async init(): Promise<void> {
    if (this.loading || !this.active) { return; }
    this.loading = true;
    this.busy = true;
    this.errorMessage = '';
    try {
      const params = router.getParams() as Record<string, Object>;
      const book = await BookRepo.getById(params !== undefined ? params['bookId'] as number : 0);
      if (!this.active) { return; }
      if (book === null || book.format !== 'pdf') {
        throw new Error('这份 PDF 已不在书库中，请重新导入。');
      }
      this.book = book;
      const initial: number = Math.max(0, Math.min(book.charCount - 1, book.progressCharOffset));
      const result: pdfService.ParseResult = await this.controller.loadDocument(book.filePath, '', initial);
      if (!this.active) {
        this.controller.releaseDocument();
        return;
      }
      if (result === pdfService.ParseResult.PARSE_ERROR_PASSWORD || result === pdfService.ParseResult.PARSE_ERROR_CERT) {
        throw new Error('PDF 需要密码或证书，请重新导入未加密的副本。');
      }
      if (result !== pdfService.ParseResult.PARSE_SUCCESS || this.controller.getPageCount() <= 0) {
        throw new Error('PDF 副本损坏或无法解析，请重新导入。');
      }
      this.loaded = true;
      this.pageCount = this.controller.getPageCount();
      this.pageIndex = Math.min(initial, this.pageCount - 1);
      this.sliderValue = this.pageIndex;
      this.bookmarks = await BookmarkRepo.listByBook(book.id);
      if (!this.active) {
        this.controller.releaseDocument();
        this.loaded = false;
        return;
      }
      this.controller.registerPageChangedListener((index: number) => this.onPageChanged(index));
      this.controller.registerScaleChangedListener((scale: number) => {
        if (this.active) { this.zoom = scale; }
      });
      this.applyLayout();
      this.controller.setPageContinuous(this.continuous);
      this.controller.setPageSpacing(16, 16);
      this.controller.goToPage(this.pageIndex);
      this.busy = false;
      this.saveProgress();
      this.resumeReading();
    } catch (e) {
      this.controller.releaseDocument();
      this.loaded = false;
      if (this.active) {
        this.errorMessage = e instanceof Error ? e.message : '暂时无法打开 PDF，请重试。';
        this.busy = false;
        this.loaded = false;
      }
    } finally {
      this.loading = false;
    }
  }

  private applyLayout(): void {
    this.spreadMode = this.wideWindow && this.settings.layoutMode !== 'single';
    if (!this.loaded) { return; }
    const anchor: number = this.pageIndex;
    this.controller.setPageLayout(this.spreadMode ? pdfService.PageLayout.LAYOUT_DOUBLE : pdfService.PageLayout.LAYOUT_SINGLE);
    this.controller.setPageFit(this.fitWidth ? pdfService.PageFit.FIT_WIDTH : pdfService.PageFit.FIT_PAGE);
    this.controller.goToPage(anchor);
  }

  private onPageChanged(index: number): void {
    if (!this.active || !this.loaded || !Number.isFinite(index)) { return; }
    this.pageIndex = Math.max(0, Math.min(this.pageCount - 1, Math.floor(index)));
    this.sliderValue = this.pageIndex;
    this.session.interact();
    this.saveProgress();
  }

  private navigateTo(index: number): void {
    if (!this.loaded || this.busy) { return; }
    const target: number = Math.max(0, Math.min(this.pageCount - 1, Math.floor(index)));
    this.controller.goToPage(target);
    // A two-page layout may align an odd requested page to the beginning of its spread.
    this.onPageChanged(this.controller.getPageIndex());
  }

  private saveProgress(): void {
    if (!this.loaded || this.book.id <= 0) { return; }
    this.pendingProgress = this.pageIndex;
    if (!this.writingProgress) {
      this.progressTask = this.flushProgress();
    }
  }

  private async flushProgress(): Promise<void> {
    this.writingProgress = true;
    try {
      while (this.pendingProgress >= 0) {
        const page: number = this.pendingProgress;
        this.pendingProgress = -1;
        await BookRepo.touchAndSetProgress(this.book.id, page);
      }
    } catch (e) {
      this.toast('阅读进度保存失败，请检查可用空间后重试');
    } finally {
      this.writingProgress = false;
    }
  }

  private async backToShelf(): Promise<void> {
    if (this.leaving) { return; }
    this.leaving = true;
    this.saveProgress();
    await this.progressTask;
    await this.session.pause().catch(() => {});
    await this.leaveImmersiveMode();
    router.back();
  }

  private currentBookmark(): Bookmark | undefined {
    return this.bookmarks.find((bookmark: Bookmark) => bookmark.charOffset === this.pageIndex);
  }

  private async toggleBookmark(): Promise<void> {
    if (!this.loaded || this.bookmarkBusy) { return; }
    this.bookmarkBusy = true;
    const page: number = this.pageIndex;
    const existing = this.currentBookmark();
    try {
      if (existing !== undefined) {
        await BookmarkRepo.remove(existing.id);
      } else {
        await BookmarkRepo.add(this.book.id, page, '第 ' + (page + 1) + ' 页 · ' + this.book.title);
      }
      this.bookmarks = await BookmarkRepo.listByBook(this.book.id);
      this.toast(existing !== undefined ? '已移除本页书签' : '已添加本页书签');
    } catch (e) {
      this.toast('书签保存失败，请重试');
    } finally {
      this.bookmarkBusy = false;
    }
  }

  private async removeBookmark(bookmark: Bookmark): Promise<void> {
    try {
      const answer = await this.getUIContext().getPromptAction().showDialog({
        title: '删除书签？', message: bookmark.excerpt,
        buttons: [{ text: '取消', color: '#8E8E93' }, { text: '删除', color: '#FF3B30' }]
      });
      if (answer.index !== 1) { return; }
      await BookmarkRepo.remove(bookmark.id);
      this.bookmarks = await BookmarkRepo.listByBook(this.book.id);
    } catch (e) {
      this.toast('未能删除书签，请重试');
    }
  }

  private async markFinished(): Promise<void> {
    try {
      await ReadingActivityRepo.setFinished(this.book.id, true);
      this.completionRecorded = true;
      this.toast('已标记为读完');
    } catch (e) { this.toast('未能标记为读完，请重试'); }
  }

  private toast(message: string): void {
    if (this.active) { this.getUIContext().getPromptAction().showToast({ message: message }); }
  }

  private openPanel(kind: string): void {
    this.panelKind = kind;
    this.panelVisible = true;
    this.pageInput = (this.pageIndex + 1).toString();
    this.session.pause().catch(() => {});
  }

  private search(): void {
    if (!this.loaded) { return; }
    const query: string = this.searchText.trim();
    this.controller.clearSearch();
    this.searchCount = 0;
    this.searchIndex = 0;
    const request: number = ++this.searchRequest;
    this.searchBusy = query.length > 0;
    if (query.length === 0) { return; }
    this.controller.searchKey(query, (count: number) => {
      if (!this.active || request !== this.searchRequest) { return; }
      this.searchBusy = false;
      this.searchCount = Math.max(0, count);
      if (count > 0) {
        this.controller.setSearchIndex(0);
        this.searchIndex = 1;
      }
    });
  }

  private nextSearchResult(): void {
    if (this.searchCount <= 0) { return; }
    const index: number = this.searchIndex % this.searchCount;
    this.controller.setSearchIndex(index);
    this.searchIndex = index + 1;
    this.panelVisible = false;
  }

  @Builder
  bottomBar() {
    Column({ space: 4 }) {
      Row({ space: 12 }) {
        Text('第 ' + (this.pageIndex + 1) + ' 页 / 共 ' + this.pageCount + ' 页')
          .id('pdf-page-label').fontSize(13).fontColor($r('app.color.label_secondary'))
        Text(this.spreadMode ? '双页' : '单页').fontSize(12).fontColor($r('app.color.label_tertiary'))
      }
      Row({ space: 12 }) {
        IconButton({ icon: $r('app.media.ic_contents'), label: 'PDF 页码、书签与搜索',
          onAction: () => this.openPanel('bookmarks') }).id('pdf-bookmarks')
        Slider({ value: this.sliderValue, min: 0, max: Math.max(1, this.pageCount - 1), step: 1 })
          .id('pdf-progress').layoutWeight(1).enabled(this.pageCount > 1).accessibilityText('PDF 阅读页码')
          .onChange((value: number, mode: SliderChangeMode) => {
            this.sliderValue = value;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.navigateTo(value); }
          })
        IconButton({ icon: $r('app.media.nav_grid'), label: 'PDF 显示设置',
          onAction: () => this.openPanel('settings') }).id('pdf-settings')
      }.width('100%')
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 8 })
    .width('96%').constraintSize({ maxWidth: 680 }).margin({ bottom: 12, top: 8 })
    .backgroundColor($r('app.color.glass_surface')).backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .borderRadius(28).border({ width: 0.75, color: $r('app.color.glass_edge') })
    .attributeModifier(new LightFeedback(this.settings.reduceMotion, true))
    .transition(ReaderMotion.reveal(this.settings.reduceMotion, 16))
  }

  @Builder
  pageTools() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        TextInput({ text: this.pageInput, placeholder: '页码' }).id('pdf-page-input')
          .type(InputType.Number).maxLength(7).layoutWeight(1).accessibilityText('跳转到 PDF 页码')
          .onChange((value: string) => { this.pageInput = value; })
        Button('前往').id('pdf-page-go').onClick(() => {
          const page: number = Number(this.pageInput);
          if (!Number.isSafeInteger(page) || page < 1 || page > this.pageCount) {
            this.toast('请输入 1 至 ' + this.pageCount + ' 之间的页码');
            return;
          }
          this.navigateTo(page - 1);
          this.panelVisible = false;
        })
      }
      Search({ value: this.searchText, placeholder: '搜索 PDF 中的文字' })
        .id('pdf-search').maxLength(200)
        .onChange((value: string) => { this.searchText = value; })
        .onSubmit(() => this.search())
      Row({ space: 12 }) {
        Text(this.searchBusy ? '正在搜索…' : (this.searchCount > 0 ?
          this.searchIndex + ' / ' + this.searchCount + ' 个结果' : '扫描件若无文字层，将无法搜索'))
          .fontSize(12).fontColor($r('app.color.label_secondary')).layoutWeight(1)
        Button('搜索').onClick(() => this.search())
        Button('下一个').enabled(this.searchCount > 0).onClick(() => this.nextSearchResult())
      }
      Row() {
        Text('书签').fontSize(20).fontWeight(600).fontColor($r('app.color.label_primary')).layoutWeight(1)
        Button(this.currentBookmark() !== undefined ? '移除本页' : '添加本页')
          .enabled(!this.bookmarkBusy).onClick(() => this.toggleBookmark())
      }
    }.padding({ left: 24, right: 24, top: 12, bottom: 12 })
    if (this.bookmarks.length === 0) {
      Text('还没有书签。把想再读的页面留在这里。')
        .fontSize(15).fontColor($r('app.color.label_secondary')).padding(24).layoutWeight(1)
    } else {
      List() {
        ForEach(this.bookmarks, (bookmark: Bookmark) => {
          ListItem() {
            Row({ space: 12 }) {
              Text(bookmark.excerpt).fontSize(16).fontColor($r('app.color.label_primary'))
                .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ top: 18, bottom: 18 }).onClick(() => {
                  this.navigateTo(bookmark.charOffset);
                  this.panelVisible = false;
                })
              IconButton({ icon: $r('app.media.ic_delete'), label: '删除第 ' + (bookmark.charOffset + 1) + ' 页书签',
                destructive: true, onAction: () => this.removeBookmark(bookmark) })
            }.padding({ left: 24, right: 16 })
          }
        }, (bookmark: Bookmark) => bookmark.id.toString())
      }.layoutWeight(1).divider({ strokeWidth: 0.5, color: $r('app.color.separator'), startMargin: 24, endMargin: 24 })
    }
  }

  @Builder
  displayTools() {
    Column({ space: 20 }) {
      Text('原生 PDF 排版').fontSize(22).fontWeight(600).fontColor($r('app.color.label_primary')).width('100%')
      Text('保留文档原版式，支持双指缩放与文字选择。字体和纸张颜色由 PDF 本身决定。')
        .fontSize(15).fontColor($r('app.color.label_secondary')).width('100%')
      Row({ space: 4 }) {
        ReadingChoice({ label: '单页', keyName: 'pdf-single', selected: this.settings.layoutMode === 'single' || !this.wideWindow,
          onChoose: () => { this.settings.layoutMode = 'single'; this.applyLayout(); } }).layoutWeight(1)
        ReadingChoice({ label: '双页', keyName: 'pdf-double', selected: this.settings.layoutMode === 'double' && this.wideWindow, disabled: !this.wideWindow,
          onChoose: () => { this.settings.layoutMode = 'double'; this.applyLayout(); } }).layoutWeight(1)
      }.width('100%').padding(4).backgroundColor($r('app.color.background')).borderRadius(16)
      if (!this.wideWindow) {
        Text('横屏或窗口宽度达到 1000 vp 时可使用双页。').fontSize(13).fontColor($r('app.color.label_secondary')).width('100%')
      }
      Row({ space: 4 }) {
        ReadingChoice({ label: '适合整页', keyName: 'pdf-fit-page', selected: !this.fitWidth,
          onChoose: () => { this.fitWidth = false; this.applyLayout(); } }).layoutWeight(1)
        ReadingChoice({ label: '适合宽度', keyName: 'pdf-fit-width', selected: this.fitWidth,
          onChoose: () => { this.fitWidth = true; this.applyLayout(); } }).layoutWeight(1)
      }.width('100%').padding(4).backgroundColor($r('app.color.background')).borderRadius(16)
      Row() {
        Text('连续滚动').fontSize(17).fontColor($r('app.color.label_primary')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.continuous }).id('pdf-continuous')
          .onChange((value: boolean) => { this.continuous = value; this.controller.setPageContinuous(value); })
      }.width('100%')
      Text('缩放 ' + Math.round(this.zoom * 100) + '%').fontSize(13).fontColor($r('app.color.label_secondary')).width('100%')
      Row({ space: 12 }) {
        Button('缩小').onClick(() => this.controller.setPageZoom(Math.max(0.1, this.controller.getPageZoom() / 1.25)))
        Button('放大').onClick(() => this.controller.setPageZoom(Math.min(10, this.controller.getPageZoom() * 1.25)))
        Button('专注阅读').id('pdf-focus').onClick(() => {
          this.getUIContext().animateTo(ReaderMotion.change(this.settings.reduceMotion), () => { this.controlsVisible = false; });
          this.panelVisible = false;
        })
      }.width('100%')
      Button(this.completionRecorded ? '已读完' : '标记为读完').id('pdf-finished')
        .onClick(() => this.markFinished())
    }.width('100%').padding(24)
  }

  @Builder
  panelBuilder() {
    Column() {
      Row() {
        Text(this.panelKind === 'settings' ? '显示设置' : '页码与书签')
          .fontSize(20).fontWeight(600).fontColor($r('app.color.label_primary')).layoutWeight(1)
        IconButton({ icon: $r('app.media.ic_close'), label: '关闭 PDF 面板', onAction: () => { this.panelVisible = false; } })
      }.padding({ left: 24, right: 16, top: 8 })
      if (this.panelKind === 'settings') {
        Scroll() { this.displayTools() }.layoutWeight(1).align(Alignment.TopStart)
      } else {
        this.pageTools()
      }
    }.width('100%').height('100%').padding({ bottom: 24 }).backgroundColor($r('app.color.surface'))
  }

  @Builder
  stateOverlay() {
    Column({ space: 16 }) {
      if (this.errorMessage.length > 0) {
        Text('暂时无法阅读 PDF').fontSize(22).fontWeight(600).fontColor($r('app.color.label_primary'))
        Text(this.errorMessage).id('pdf-error').fontSize(16).fontColor($r('app.color.label_secondary'))
          .textAlign(TextAlign.Center).constraintSize({ maxWidth: 360 })
        Row({ space: 16 }) {
          Button('返回书库').onClick(() => this.backToShelf())
          Button('重试').onClick(() => this.init())
        }
      } else {
        LoadingProgress().width(32).height(32)
        Text('正在打开 PDF…').fontSize(16).fontColor($r('app.color.label_secondary'))
      }
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
      .backgroundColor($r('app.color.surface'))
  }

  build() {
    GridRow({ columns: 12, breakpoints: { value: ['1000vp'], reference: BreakpointsReference.WindowSize } }) {
      GridCol({ span: 12 }) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Column() {
            if (this.controlsVisible) {
              HudTopBar({ title: this.book.title, bookmarked: this.currentBookmark() !== undefined,
                onBack: () => this.backToShelf(), onBookmark: () => this.toggleBookmark() })
                .id('pdf-top-bar')
                .transition(ReaderMotion.reveal(this.settings.reduceMotion, -16))
            }
            PdfView({ controller: this.controller, pageLayout: pdfService.PageLayout.LAYOUT_SINGLE,
              isContinuous: false, showScroll: true, pageFit: pdfService.PageFit.FIT_PAGE })
              .id('pdf-view').width('100%').layoutWeight(1)
              .onAppear(() => this.init())
              .onTouch(() => this.session.interact())
            if (this.controlsVisible) { this.bottomBar() }
          }.width('100%').height('100%').padding({ top: this.safeTop, bottom: this.safeBottom })
          if (!this.controlsVisible && this.loaded) {
            Button('显示工具').id('pdf-show-controls').margin({ top: this.safeTop + 12, right: 16 })
              .attributeModifier(new LightFeedback(this.settings.reduceMotion))
              .onClick(() => this.getUIContext().animateTo(ReaderMotion.change(this.settings.reduceMotion), () => { this.controlsVisible = true; }))
          }
          if (this.busy || this.errorMessage.length > 0) { this.stateOverlay() }
        }.width('100%').height('100%')
          .bindSheet($$this.panelVisible, this.panelBuilder(), {
            height: SheetSize.LARGE, dragBar: true, showClose: false,
            preferType: this.wideWindow ? SheetType.CENTER : SheetType.BOTTOM,
            width: this.wideWindow ? 540 : '100%', backgroundColor: $r('app.color.surface'),
            blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
            onDisappear: () => this.resumeReading()
          })
      }.height('100%')
    }.width('100%').height('100%').backgroundColor($r('app.color.surface'))
      .onBreakpointChange((breakpoint: string) => {
        this.wideWindow = breakpoint !== 'xs';
        this.applyLayout();
      })
  }
}
