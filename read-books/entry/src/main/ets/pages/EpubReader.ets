import { router, window, mediaquery, PersistenceV2, AnimatorResult } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book, Bookmark } from '../model/Models';
import { BookRepo } from '../data/BookRepo';
import { BookmarkRepo } from '../data/BookmarkRepo';
import { ReadingActivityRepo } from '../data/ReadingActivityRepo';
import { ReadingSettings } from '../model/ReadingSettings';
import { ReadingFonts } from '../reader/ReadingFonts';
import { AppPreferences } from '../model/AppPreferences';
import { ReadingPalette, ThemeManager } from '../theme/ThemeManager';
import { ReaderMotion } from '../theme/ReaderMotion';
import { ReadingRefresh } from '../theme/ReadingRefresh';
import { ReadingSettingsPanel } from '../components/ReadingSettingsPanel';
import { HudTopBar, HudBottomBar } from '../components/HudBar';
import { IconButton } from '../components/IconButton';
import { ReadingSession } from '../reader/ReadingSession';
import { EpubSection } from '../reader/EpubSource';
import { EpubNavEntry } from '../reader/EpubDocument';
import { EpubResources, epubUrl, epubRequestPath } from '../reader/EpubResources';
import { EpubRenderPool } from '../reader/EpubRenderPool';
import { EpubBoundaryDrag, EpubFollowupInput, canPromoteSettlingChapter } from '../reader/EpubBoundaryDrag';
import { PageSettle, pageSettle } from '../reader/PageTurnMotion';
import { WindowMode } from '../utils/WindowMode';

class EpubTocSource implements IDataSource {
  private items: EpubNavEntry[] = [];
  private listeners: DataChangeListener[] = [];
  update(items: EpubNavEntry[]): void { this.items = items; this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded()); }
  totalCount(): number { return this.items.length; }
  getData(index: number): EpubNavEntry { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener); } }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener); }
}

class EpubLocator {
  path: string = '';
  element: number = -1;
  fraction: number = 0;
}
class EpubMessage {
  fragment: string = '';
  type: string = '';
  page: number = 0;
  pages: number = 1;
  locator: EpubLocator = new EpubLocator();
  delta: number = 0;
  carry: number = 0;
  href: string = '';
  timing: string = '';
  vertical: boolean = false;
  rtl: boolean = false;
  selected: boolean = false;
}
class EpubConfiguration {
  token: string = '';
  fixed: boolean = false;
  spread: boolean = false;
  gutter: number = 24;
  publisher: boolean = true;
  fontSize: number = 18;
  lineHeight: number = 1.55;
  font: string = '';
  background: boolean = false;
  dark: boolean = false;
  paper: boolean = false;
  bg: string = '#FFFFFF';
  text: string = '#202020';
  reduceMotion: boolean = false;
  warm: boolean = true;
  nativeBoundary: boolean = true;
  fragment: string = '';
}

@Entry
@ComponentV2
struct EpubReader {
  @Local book: Book = new Book();
  @Local settings: ReadingSettings = ReadingSettings.load();
  @Local preferences: AppPreferences = AppPreferences.load();
  @Local dark: boolean = false;
  @Local wide: boolean = false;
  @Local busy: boolean = true;
  @Local error: string = '';
  @Local source: string = '';
  @Local sources: string[] = ['', '', '', ''];
  @Local visibleSlot: number = 0;
  @Local outgoingSlot: number = -1;
  @Local dragSlot: number = -1;
  @Local dragOffset: number = 0;
  @Local dragSide: number = 1;
  @Local hasPage: boolean = false;
  @Local page: number = 0;
  @Local pages: number = 1;
  @Local sectionIndex: number = 0;
  @Local controls: boolean = true;
  @Local panel: boolean = false;
  @Local panelKind: string = 'settings';
  @Local bookmarkTab: boolean = false;
  @Local query: string = '';
  @Local toc: EpubNavEntry[] = [];
  @Local fragment: string = '';
  @Local bookmarks: Bookmark[] = [];
  private sections: EpubSection[] = [];
  private tocSource: EpubTocSource = new EpubTocSource();
  private controller: webview.WebviewController = new webview.WebviewController();
  private controllers: webview.WebviewController[] = [this.controller, new webview.WebviewController(),
    new webview.WebviewController(), new webview.WebviewController()];
  private pool: EpubRenderPool = new EpubRenderPool();
  private drag: EpubBoundaryDrag = new EpubBoundaryDrag();
  private followupInput: EpubFollowupInput = new EpubFollowupInput();
  private queuedInput: boolean = false;
  private refresh: ReadingRefresh = new ReadingRefresh();
  private surfaceWidth: number = 1;
  private surfaceHeight: number = 1;
  private dragSettling: boolean = false;
  private dragCommit: boolean = false;
  private dragEpoch: number = 0;
  private turnAnimator: AnimatorResult | null = null;
  private settleCommits: boolean = false;
  private continuationSlot: number = -1;
  private continuationIncoming: boolean = true;
  private continuationMoveBusy: boolean = false;
  private continuationMoveVersion: number = 0;
  private continuationFraction: number = 0;
  private layoutVersion: number = 0;
  private pendingSeekDone: boolean = false;
  private resources: EpubResources = new EpubResources();
  private session: ReadingSession = new ReadingSession();
  private active: boolean = false;
  private foreground: boolean = true;
  private leaving: boolean = false;
  private immersiveReady: boolean = false;
  private documentReady: boolean = false;
  private engine: string = '';
  private token: string = '';
  private locator: EpubLocator = new EpubLocator();
  private pendingLocator: EpubLocator | null = null;
  private pendingFragment: string = '';
  @Local path: string = '';
  private timer: number = -1;
  private heartbeat: number = -1;
  private saveTimer: number = -1;
  private saveTask: Promise<void> = Promise.resolve();
  private generation: number = 0;
  private readerWindow: window.Window | null = null;
  private listener: mediaquery.MediaQueryListener | null = null;
  private resourceWarning: boolean = false;
  private chapterStarted: number = 0;
  private blendTimer: number = -1;
  private prefetchTimer: number = -1;
  private handoffToken: string = '';
  private queuedTurns: number = 0;
  private windowEvent = (event: window.WindowEventType): void => {
    if (event === window.WindowEventType.WINDOW_HIDDEN) {
      this.resetDrag();
      this.foreground = false; this.save(); this.session.pause().catch(() => {});
    } else if (event === window.WindowEventType.WINDOW_SHOWN) { this.foreground = true; this.resume(); }
  };

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.resources.loadBuiltinFont = (resource: string): Promise<Uint8Array> => context.resourceManager.getRawFileContent(resource);
    this.resources.onPrefetchReady = (count: number, bytes: number): void => {
      hilog.info(0, 'ReadBooksEpubPerf', 'prefetchChapters=%{public}d bytes=%{public}d', count, bytes);
    };
    this.active = true;
    this.listener = mediaquery.matchMediaSync('(prefers-color-scheme: dark)');
    this.dark = this.listener.matches;
    this.listener.on('change', (result: mediaquery.MediaQueryResult) => { this.dark = result.matches; this.reflow(); });
    this.init();
    this.heartbeat = setInterval(() => { this.save(); this.session.flush().catch(() => {}); }, 30000);
  }
  onPageShow(): void { this.foreground = true; this.resume(); }
  pageTransition() {
    PageTransitionEnter(ReaderMotion.pageEnter(this.settings.reduceMotion))
      .opacity(this.settings.reduceMotion ? 1 : 0)
      .translate({ y: this.settings.reduceMotion ? 0 : 20 })
      .scale({ x: this.settings.reduceMotion ? 1 : 0.985, y: this.settings.reduceMotion ? 1 : 0.985 })
      .onEnter((_type: RouteType, progress: number) => {
        if (progress >= 1 && this.active && !this.leaving && this.readerWindow === null) {
          this.immersive();
        }
      })
    PageTransitionExit(ReaderMotion.pageExit(this.settings.reduceMotion))
      .opacity(this.settings.reduceMotion ? 1 : 0)
      .translate({ y: this.settings.reduceMotion ? 0 : 16 })
  }
  onPageHide(): void { this.resetDrag(); this.foreground = false; this.save(); this.session.pause().catch(() => {}); }
  onBackPress(): boolean {
    if (this.panel) { this.panel = false; return true; }
    this.back(); return true;
  }
  aboutToDisappear(): void {
    this.resetDrag();
    this.refresh.dispose();
    this.save(); this.active = false; this.generation++;
    clearInterval(this.heartbeat); clearTimeout(this.timer); clearTimeout(this.saveTimer);
    clearTimeout(this.prefetchTimer);
    clearTimeout(this.blendTimer);
    this.listener?.off('change');
    this.session.pause().catch(() => {});
    this.resources.close().catch(() => {});
    this.leaveImmersive();
  }
  private async immersive(): Promise<void> {
    try {
      const win = await window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext);
      if (!this.active) { return; }
      this.readerWindow = win;
      this.wide = px2vp(win.getWindowProperties().windowRect.width) >= 1000;
      win.on('windowEvent', this.windowEvent);
      await WindowMode.setReaderMode(win, true);
    } catch (_) {}
    if (this.active && !this.leaving) {
      this.immersiveReady = true;
      if (this.pool.pending >= 0) { this.startSurface(this.pool.pending); }
    }
  }
  private async leaveImmersive(): Promise<void> {
    const win = this.readerWindow; this.readerWindow = null;
    if (win !== null) { try { win.off('windowEvent', this.windowEvent); await WindowMode.setReaderMode(win, false); } catch (_) {} }
  }
  private async back(): Promise<void> {
    if (this.leaving) { return; }
    this.leaving = true; this.save();
    await this.saveTask;
    await this.session.pause().catch(() => {});
    await this.leaveImmersive();
    router.back();
  }
  private palette(): ReadingPalette { return ThemeManager.resolve(this.settings.theme, this.dark, this.preferences.appearance); }
  private isNight(): boolean { return ThemeManager.chromeDark(this.settings.theme, this.dark, this.preferences.appearance); }
  private resume(): void { if (this.active && this.foreground && this.documentReady && !this.panel && !this.busy) { this.session.resume(); } }
  private toast(message: string): void { if (this.active) { this.getUIContext().getPromptAction().showToast({ message: message }); } }

  private async init(): Promise<void> {
    try {
      const params = router.getParams() as Record<string, Object>;
      const book = await BookRepo.getById(params['bookId'] as number);
      if (!book || !book.sourcePath) { throw new Error('缺少 EPUB 原版，请从书库补全原文件'); }
      this.book = book;
      this.sections = JSON.parse(book.epubIndex) as EpubSection[];
      if (!this.sections.length) { throw new Error('EPUB 阅读顺序缺失'); }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.engine = util.TextDecoder.create('utf-8').decodeToString(await context.resourceManager.getRawFileContent('epub-engine.js'));
      await this.resources.open(book.sourcePath);
      if (!this.active) { await this.resources.close(); return; }
      this.resources.onFailure = (message: string) => {
        if (!this.resourceWarning) { this.resourceWarning = true; this.toast('部分书内资源未加载：' + message); }
      };
      this.toc = this.resources.navigation.length ? this.resources.navigation : this.sections.map((section: EpubSection) => {
        const item = new EpubNavEntry(); item.title = section.title; item.path = section.path; return item;
      });
      this.filterToc();
      this.bookmarks = await BookmarkRepo.listByBook(book.id);
      let location: EpubLocator | null = null;
      try {
        const saved = JSON.parse(book.epubLocation) as EpubLocator;
        if (typeof saved.path === 'string' && this.resources.has(saved.path)) { location = saved; }
      } catch (_) {}
      if (location) { this.navigate(location.path, '', location); }
      else { this.navigateOffset(book.progressCharOffset); }
    } catch (e) { if (this.active) { this.error = e instanceof Error ? e.message : '无法打开 EPUB'; this.busy = false; } }
  }

  private navigate(path: string, fragment: string = '', location: EpubLocator | null = null, carry: number = 0): void {
    if (!this.active || !this.resources.has(path)) { this.toast('书内链接的目标文件不存在'); return; }
    this.save();
    this.chapterStarted = Date.now();
    clearTimeout(this.prefetchTimer);
    this.handoffToken = this.token; this.queuedTurns = carry;
    this.generation++; this.busy = true; this.error = ''; this.pendingSeekDone = false;
    this.pendingLocator = location; this.pendingFragment = fragment;
    const index = this.sections.findIndex((item: EpubSection) => item.path === path);
    this.pool.pending = -1;
    const id: number = this.pool.reserve(path, index);
    if (id < 0) { this.busy = false; return; }
    this.pool.pending = id;
    const slot = this.pool.slots[id];
    if (slot.path === path && slot.version === this.layoutVersion) {
      if (slot.ready) { this.finishPending(id); }
      return;
    }
    this.prepareSlot(id, path, index, location, fragment);
  }
  private navigateOffset(offset: number): void {
    const bounded = Math.max(0, Math.min(this.book.charCount - 1, Math.round(offset)));
    let index: number = this.sections.findIndex((section: EpubSection) => bounded >= section.start && bounded < section.end);
    if (index < 0) { index = 0; }
    const section = this.sections[index];
    const target = new EpubLocator(); target.path = section.path;
    target.fraction = (bounded - section.start) / Math.max(1, section.end - section.start);
    this.navigate(section.path, '', target);
  }
  private positionOffset(): number {
    const section = this.sections[this.sectionIndex];
    if (!section) { return 0; }
    return Math.min(this.book.charCount - 1, Math.max(0, section.start + Math.floor(this.locator.fraction * Math.max(0, section.end - section.start - 1))));
  }
  private configuration(id: number = this.pool.current): EpubConfiguration {
    const config = new EpubConfiguration();
    const slot = this.pool.slots[Math.max(0, id)];
    config.token = slot.token; config.fixed = this.sections[slot.index]?.fixed ?? false;
    config.spread = this.wide && this.settings.layoutMode === 'double' && !config.fixed;
    config.gutter = this.wide ? 48 : 24;
    config.publisher = this.settings.publisherStyle; config.fontSize = this.settings.fontSize;
    config.lineHeight = this.settings.lineHeight;
    this.resources.fontPath = this.settings.fontPath;
    this.resources.backgroundPath = this.settings.backgroundPath;
    const fontRequest: string = ReadingFonts.request(this.settings);
    config.font = fontRequest ? this.resources.origin + fontRequest : '';
    config.background = this.settings.backgroundPath.length > 0;
    config.dark = this.isNight(); config.paper = this.settings.theme === 'paper';
    config.bg = this.palette().bg; config.text = this.palette().text;
    config.reduceMotion = this.settings.reduceMotion;
    config.warm = id !== this.pool.current;
    return config;
  }
  private prepareSlot(id: number, path: string, index: number, location: EpubLocator | null, fragment: string = ''): void {
    const slot = this.pool.slots[id];
    const reuse: boolean = slot.path === path && slot.loaded;
    slot.path = path; slot.index = index; slot.revision++; slot.version = this.layoutVersion; slot.ready = false;
    slot.startedAt = Date.now();
    slot.token = 'READBOOKS_' + id + '_' + Date.now() + '_' + slot.revision + ':';
    slot.target = JSON.stringify(location); slot.anchor = fragment;
    if (reuse) { this.layoutSlot(id); }
    else { slot.loaded = false; this.startSurface(id); }
  }
  private startSurface(id: number): void {
    if (!this.immersiveReady || !this.pool.slots[id].path) { return; }
    const slot = this.pool.slots[id];
    const url = epubUrl(slot.path, '', this.resources.origin);
    this.source = url;
    if (!slot.attached) {
      const sources = this.sources.slice(); sources[id] = url; this.sources = sources;
    } else {
      try { this.controllers[id].loadUrl(url); }
      catch (_) { if (this.pool.pending === id) { this.error = '无法加载章节'; this.busy = false; } }
    }
  }
  private async loadedSlot(id: number, url: string): Promise<void> {
    const slot = this.pool.slots[id];
    if (!this.active || slot.loaded) { return; }
    try { if (epubRequestPath(url, this.resources.origin) !== slot.path) { return; } } catch (_) { return; }
    const revision: number = slot.revision;
    try {
      await this.controllers[id].runJavaScript(this.engine);
      if (!this.active || revision !== slot.revision) { return; }
      slot.loaded = true;
      hilog.info(0, 'ReadBooksEpubPerf', 'htmlLoadedChapter=%{public}d elapsedMs=%{public}d',
        slot.index, Date.now() - slot.startedAt);
      this.layoutSlot(id);
    } catch (_) {
      if (this.active && revision === slot.revision && this.pool.pending === id) { this.error = '图文排版未能完成，请返回后重试'; this.busy = false; }
    }
  }
  private layoutSlot(id: number): void {
    const slot = this.pool.slots[id];
    const revision: number = slot.revision;
    const config = this.configuration(id); config.fragment = slot.anchor;
    this.controllers[id].runJavaScript('window.ReadBooks.prepare(' + JSON.stringify(config) + ',' + slot.target + ')')
      .catch(() => { if (this.active && revision === slot.revision && this.pool.pending === id) { this.error = '图文排版未能完成'; this.busy = false; } });
  }
  private finishPending(id: number): void {
    if (!this.active || this.pool.pending !== id || !this.pool.slots[id].ready) { return; }
    const slot = this.pool.slots[id];
    if (slot.version !== this.layoutVersion) {
      this.pendingSeekDone = false;
      this.prepareSlot(id, slot.path, slot.index, this.pendingLocator, this.pendingFragment);
      return;
    }
    const location = this.pendingLocator;
    const fraction: number = location?.fraction ?? 0;
    const atTarget: boolean = !this.pendingFragment && (location?.element ?? -1) < 0 &&
      ((fraction === 0 && slot.page === 0) || (fraction === 1 && slot.page === slot.pages - 1));
    if (!this.pendingSeekDone && !atTarget) {
      this.pendingSeekDone = true; slot.ready = false;
      this.controllers[id].runJavaScript('window.ReadBooks.seek(' + JSON.stringify(location) + ',' + JSON.stringify(this.pendingFragment) + ')')
        .catch(() => { if (this.pool.pending === id) { this.error = '阅读位置未能恢复'; this.busy = false; } });
      return;
    }
    const prior: number = this.pool.current;
    this.pool.current = id; this.pool.pending = -1; this.controller = this.controllers[id];
    if (prior >= 0 && prior !== id) {
      this.controllers[prior].runJavaScript('window.ReadBooks.holdInput(true)').catch(() => {});
    }
    this.token = slot.token; this.path = slot.path; this.resources.mainPath = slot.path; this.sectionIndex = slot.index;
    this.page = slot.page; this.pages = slot.pages; this.fragment = slot.fragment;
    const locator = new EpubLocator(); locator.path = slot.path; locator.element = slot.element; locator.fraction = slot.fraction; this.locator = locator;
    this.documentReady = true; this.busy = false; this.pendingLocator = null; this.pendingFragment = '';
    clearTimeout(this.blendTimer);
    if (prior < 0 || this.dragCommit) { this.visibleSlot = id; this.hasPage = true; this.resetDrag(true); }
    else {
      // Keep the outgoing surface opaque beneath the incoming fade. Fading both
      // exposes the paper/background in the middle and looks like a brightness flash.
      this.outgoingSlot = prior;
      this.getUIContext().animateTo({ duration: this.settings.reduceMotion ? 0 : 90, curve: Curve.Linear,
        expectedFrameRateRange: this.settings.reduceMotion ? undefined : ReadingRefresh.range() }, () => { this.visibleSlot = id; });
      this.blendTimer = setTimeout(() => { if (this.active) { this.outgoingSlot = -1; } }, 100);
    }
    hilog.info(0, 'ReadBooksEpubPerf', 'chapter=%{public}d readyMs=%{public}d preparedSurface=true', slot.index, Date.now() - this.chapterStarted);
    this.save(); this.resume();
    const queued: number = this.queuedTurns; this.queuedTurns = 0; this.handoffToken = '';
    this.controller.runJavaScript('window.ReadBooks.holdInput(false);' + (queued ? 'window.ReadBooks.go(' + queued + ');' : '')).catch(() => {});
    this.scheduleWarm();
  }
  private scheduleWarm(): void {
    clearTimeout(this.prefetchTimer);
    this.prefetchTimer = setTimeout(() => {
      if (!this.active || this.busy || !this.documentReady || !this.foreground) { return; }
      // Neighbour layout has a deadline; only distant byte prefetch yields to touch.
      // Sharing the old 380 ms debounce starved the very next chapter during rapid turns.
      this.resources.prefetchWindow(this.sections.slice(this.sectionIndex, this.sectionIndex + 50).map((section: EpubSection) => section.path));
      const neighbours: number[] = [this.sectionIndex + 1, this.sectionIndex + 2, this.sectionIndex - 1];
      for (const index of neighbours) {
        if (index < 0 || index >= this.sections.length) { continue; }
        const path: string = this.sections[index].path;
        const existing: number = this.pool.find(path);
        if (existing >= 0 && this.pool.slots[existing].version === this.layoutVersion) {
          const slot = this.pool.slots[existing];
          const edge = index < this.sectionIndex ? slot.pages - 1 : 0;
          if (slot.ready && slot.page !== edge && existing !== this.dragSlot) {
            slot.ready = false;
            const target = new EpubLocator(); target.path = path; target.fraction = index < this.sectionIndex ? 1 : 0;
            this.controllers[existing].runJavaScript('window.ReadBooks.seek(' + JSON.stringify(target) + ',"")').catch(() => { slot.version = -1; });
          }
        } else {
          const keep: string[] = neighbours.filter((other: number) => other !== index && other >= 0 && other < this.sections.length)
            .map((other: number) => this.sections[other].path);
          const id: number = this.pool.reserve(path, index, keep);
          if (id >= 0) {
            const target = new EpubLocator(); target.path = path; target.fraction = index < this.sectionIndex ? 1 : 0;
            this.prepareSlot(id, path, index, target);
          }
        }
        // Two simultaneous Web loads fight over one ZIP descriptor and image decoder.
        // Complete the immediate next spread before spending resources farther ahead.
        if (index === this.sectionIndex + 1 && this.readyNeighbour(1) < 0) { return; }
      }
    }, 24);
  }
  private slotMessage(id: number, text: string): boolean {
    const slot = this.pool.slots[id];
    if (!this.active || this.leaving || !text.startsWith(slot.token)) { return false; }
    try {
      const value = JSON.parse(text.substring(slot.token.length)) as EpubMessage;
      if (value.type === 'position') {
        slot.page = value.page; slot.pages = Math.max(1, value.pages); slot.element = value.locator.element;
        slot.fraction = value.locator.fraction; slot.fragment = value.fragment;
        slot.vertical = value.vertical; slot.rtl = value.rtl;
      } else if (value.type === 'selection') {
        slot.selected = value.selected;
        if (id === this.pool.current && slot.selected) { this.resetDrag(); }
        return true;
      } else if (value.type === 'ready') {
        slot.ready = true;
        if (value.timing) {
          hilog.info(0, 'ReadBooksEpubPerf', 'preparedChapter=%{public}d totalMs=%{public}d stagesMs=%{public}s',
            slot.index, Date.now() - slot.startedAt, value.timing);
        }
        if (id === this.pool.pending) { this.finishPending(id); }
        else {
          hilog.info(0, 'ReadBooksEpubPerf', 'warmChapter=%{public}d slot=%{public}d readyMs=%{public}d',
            slot.index, id, Date.now() - slot.startedAt);
          if (slot.index === this.sectionIndex + 1) { this.scheduleWarm(); }
        }
        return true;
      } else if (value.type === 'error' && id !== this.pool.current) {
        slot.version = -1;
        if (id === this.pool.pending) { this.error = '章节排版未能完成'; this.busy = false; }
        return true;
      }
      if (id !== this.pool.current) { return true; }
      return this.message(text);
    } catch (_) { return false; }
  }
  private message(text: string): boolean {
    if (!this.active || this.leaving) { return false; }
    // Only turn intents from the immediately outgoing, trusted engine may cross a handoff.
    // Its position reports must never overwrite the new chapter's locator.
    if (this.busy && this.handoffToken && text.startsWith(this.handoffToken)) {
      try {
        const pending = JSON.parse(text.substring(this.handoffToken.length)) as EpubMessage;
        if (pending.type === 'turn' && Number.isFinite(pending.delta)) {
          this.queuedTurns += pending.delta < 0 ? -1 : 1;
        }
      } catch (_) {}
      return true;
    }
    if (!text.startsWith(this.token)) { return false; }
    try {
      const value = JSON.parse(text.substring(this.token.length)) as EpubMessage;
      if (value.type === 'error') {
        this.error = '章节排版未能完成，请返回后重试'; this.busy = false;
      } else if (value.type === 'position' && Number.isFinite(value.page) && Number.isFinite(value.pages)) {
        if (this.leaving) { return true; }
        this.page = value.page; this.pages = Math.max(1, value.pages);
        this.fragment = typeof value.fragment === 'string' ? value.fragment : '';
        this.locator = value.locator; this.locator.path = this.path;
        clearTimeout(this.saveTimer); this.saveTimer = setTimeout(() => this.save(), 300);
      } else if (value.type === 'turn') {
        const carry: number = Number.isFinite(value.carry) ? Math.trunc(value.carry) : 0;
        if (this.busy) { this.queuedTurns += (value.delta < 0 ? -1 : 1) + carry; return true; }
        const index = this.sectionIndex + (value.delta < 0 ? -1 : 1);
        if (index >= 0 && index < this.sections.length) {
          const target = new EpubLocator(); target.path = this.sections[index].path; target.fraction = value.delta < 0 ? 1 : 0;
          this.navigate(target.path, '', target, carry);
        } else { this.toast(value.delta < 0 ? '已经是全书开头' : '已经读到全书结尾'); }
      } else if (value.type === 'controls') {
        this.getUIContext().animateTo(ReaderMotion.change(this.settings.reduceMotion), () => { this.controls = !this.controls; });
      } else if (value.type === 'link' && typeof value.href === 'string') {
        try {
          const path = epubRequestPath(value.href, this.resources.origin);
          const hash = value.href.indexOf('#');
          const fragment = hash >= 0 ? value.href.substring(hash + 1) : '';
          if (path === this.path && fragment) { this.controller.runJavaScript('window.ReadBooks.anchor(' + JSON.stringify(fragment) + ')').catch(() => {}); }
          else { this.navigate(path, fragment); }
        } catch (_) { this.toast('当前为离线阅读，外部链接不会打开'); }
      }
      this.session.interact();
    } catch (_) {}
    return true;
  }
  private save(): void {
    if (!this.documentReady || this.book.id <= 0) { return; }
    const offset = this.positionOffset(); const locator = JSON.stringify(this.locator);
    this.saveTask = BookRepo.touchAndSetProgress(this.book.id, offset, locator).catch(() => this.toast('阅读进度保存失败，请检查存储空间'));
  }
  @Monitor('settings.fontFamily', 'settings.fontChoice', 'settings.backgroundPath', 'settings.backgroundOpacity', 'settings.publisherStyle',
    'settings.theme', 'settings.layoutMode', 'settings.fontSize', 'settings.lineHeight', 'settings.reduceMotion')
  changed(): void { this.reflow(); }
  private reflow(): void {
    this.resetDrag();
    PersistenceV2.save('reading_settings');
    clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      if (!this.active) { return; }
      this.layoutVersion++; this.pool.invalidate();
      if (this.documentReady) {
        this.pool.slots[this.pool.current].version = this.layoutVersion;
        this.controller.runJavaScript('window.ReadBooks.layout(' + JSON.stringify(this.configuration()) + ')').catch(() => this.toast('排版更新失败'));
      }
      if (this.pool.pending >= 0) {
        const id = this.pool.pending;
        const slot = this.pool.slots[id];
        this.pendingSeekDone = false;
        this.prepareSlot(id, slot.path, slot.index, this.pendingLocator, this.pendingFragment);
      }
      this.scheduleWarm();
    }, 80);
  }
  private openPanel(kind: string): void { this.resetDrag(); this.panelKind = kind; this.panel = true; this.session.pause().catch(() => {}); }

  private resetDrag(keepFollowup: boolean = false): void {
    if (!keepFollowup) { this.followupInput.reset(); this.queuedInput = false; this.queuedTurns = 0; }
    this.stopTurnAnimator();
    this.continuationMoveVersion++; this.continuationMoveBusy = false;
    if (this.continuationSlot >= 0) {
      this.controllers[this.continuationSlot].runJavaScript('window.ReadBooks.externalCancel()').catch(() => {});
      this.continuationSlot = -1;
    }
    if ((this.dragSettling || this.dragSlot >= 0) && this.pool.current >= 0) {
      this.controller.runJavaScript('window.ReadBooks && window.ReadBooks.holdInput(false)').catch(() => {});
    }
    this.refresh.stop();
    this.dragEpoch++; this.drag.reset(); this.dragSlot = -1; this.dragOffset = 0;
    this.dragSettling = false; this.dragCommit = false;
  }
  private readyNeighbour(delta: number): number {
    const index = this.sectionIndex + delta;
    if (index < 0 || index >= this.sections.length) { return -1; }
    const id = this.pool.find(this.sections[index].path);
    if (id < 0 || id === this.pool.current) { return -1; }
    const slot = this.pool.slots[id];
    const edge = delta < 0 ? slot.pages - 1 : 0;
    return slot.ready && slot.version === this.layoutVersion && slot.page === edge ? id : -1;
  }
  private surfaceX(id: number): number {
    if (this.dragSlot < 0) { return 0; }
    if (id === this.pool.current) { return this.dragOffset; }
    return id === this.dragSlot ? this.dragSide * this.surfaceWidth + this.dragOffset : 0;
  }
  private boundaryTouch(id: number, event: TouchEvent): void {
    if (id !== this.pool.current || this.panel || this.busy || this.dragSettling || this.followupInput.down || !this.documentReady) { return; }
    this.resources.deferPrefetch();
    const slot = this.pool.slots[id];
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.refresh.end(); }
    if (slot.vertical || slot.selected) { return; }
    const point = event.type === TouchType.Up ? event.changedTouches[0] : event.touches[0];
    if (event.type === TouchType.Cancel || !point || (event.type !== TouchType.Up && event.touches.length !== 1)) {
      this.settleDrag(false); return;
    }
    if (event.type === TouchType.Down) {
      this.refresh.begin(this.settings.reduceMotion);
      clearTimeout(this.blendTimer); this.outgoingSlot = -1;
      this.drag.start(point.windowX, point.windowY, this.page, this.pages, slot.rtl, this.surfaceWidth);
      this.session.interact(); return;
    }
    if (!this.drag.move(point.windowX, point.windowY)) { return; }
    const neighbour = this.readyNeighbour(this.drag.delta);
    if (neighbour >= 0) {
      this.dragSide = this.drag.side; this.dragSlot = neighbour;
      // ArkUI already dispatches/coalesces touch input with frames. A second vsync
      // callback here adds a frame of latency between the finger and both surfaces.
      this.dragOffset = this.drag.offset;
    }
    // A cold neighbour never reveals an empty surface; hold the current page until it is ready.
    if (event.type === TouchType.Up) { this.settleDrag(this.drag.commit()); }
  }
  private settleFollowup(event: TouchEvent): void {
    if (!this.active || this.leaving || this.panel || !this.documentReady || this.pool.current < 0) {
      this.followupInput.reset(); this.queuedInput = false; return;
    }
    const point = event.type === TouchType.Up ? event.changedTouches[0] : event.touches[0];
    if (this.queuedInput) {
      if (event.type === TouchType.Cancel || !point) { this.followupInput.reset(); this.queuedInput = false; return; }
      if (event.type === TouchType.Up) {
        const delta = this.followupInput.finish(point.windowX, point.windowY);
        this.queuedInput = false;
        if (delta) {
          if (this.busy) { this.queuedTurns = Math.max(-16, Math.min(16, this.queuedTurns + delta)); }
          else { this.controller.runJavaScript('window.ReadBooks.go(' + delta + ')').catch(() => {}); }
        }
      }
      return;
    }
    if (event.type === TouchType.Down && this.busy && this.hasPage && point && event.touches.length === 1) {
      // A rare cold chapter must not swallow the next swipe while its Web finishes layout.
      const slot = this.pool.slots[this.pool.current];
      if (!slot.vertical && !slot.selected) {
        this.followupInput.start(point.windowX, point.windowY, slot.rtl, this.surfaceWidth);
        this.queuedInput = true;
      }
      return;
    }
    if (event.type === TouchType.Cancel || !point || (event.type !== TouchType.Up && event.touches.length !== 1)) {
      if (this.followupInput.down) {
        // Keep the last finger displacement until both surfaces settle home.
        this.followupInput.down = false; this.finishContinuation(0);
      }
      return;
    }
    if (event.type === TouchType.Down && this.dragSettling && this.dragSlot >= 0) {
      const incoming = this.dragSlot;
      if (canPromoteSettlingChapter(this.settleCommits, this.pool.slots[incoming].ready,
        this.dragOffset, this.surfaceWidth)) {
        hilog.info(0, 'ReadBooksEpubPerf', 'fastPromote chapter=%{public}d next=%{public}d', this.sectionIndex, this.pool.slots[incoming].index);
        // A fast reader can put down another finger before the previous settle ends.
        // Completing the already-committed pair here prevents each new gesture from
        // cancelling and restarting its remaining animation indefinitely.
        const side = this.dragSide;
        this.stopTurnAnimator();
        this.continuationSlot = -1; // A prior externalFinish is queued; do not cancel it.
        this.dragOffset = -side * this.surfaceWidth;
        this.completeTurn(true);
        const active = this.pool.current;
        if (active >= 0 && point.windowY >= 84 && point.windowY < this.surfaceHeight - 120) {
          const slot = this.pool.slots[active];
          if (!slot.vertical && !slot.selected) {
            this.continuationSlot = active; this.continuationIncoming = false;
            this.continuationMoveVersion++; this.continuationMoveBusy = false;
            this.followupInput.start(point.windowX, point.windowY, slot.rtl, this.surfaceWidth, 0, side);
            this.refresh.begin(this.settings.reduceMotion);
            this.controllers[active].runJavaScript('window.ReadBooks.externalStart()').catch(() => {});
          }
        }
        return;
      }
      const id = this.settleCommits ? this.dragSlot : this.pool.current;
      const slot = this.pool.slots[id];
      if (!slot.vertical && !slot.selected && point.windowY >= 84 && point.windowY < this.surfaceHeight - 120) {
        // onFrame owns the actual displayed translation, not the previous animation's target.
        // Invalidate callbacks BEFORE cancel: Animator.cancel emits a final onFrame.
        this.stopTurnAnimator(); this.dragSettling = false;
        this.continuationSlot = id; this.continuationIncoming = this.settleCommits;
        this.continuationMoveVersion++; this.continuationMoveBusy = false;
        const gap = this.continuationIncoming ? this.dragSide * this.surfaceWidth + this.dragOffset : this.dragOffset;
        this.followupInput.start(point.windowX, point.windowY, slot.rtl, this.surfaceWidth, gap,
          this.continuationIncoming ? this.dragSide : -this.dragSide);
        this.refresh.begin(this.settings.reduceMotion);
        this.controllers[id].runJavaScript('window.ReadBooks.externalStart()').catch(() => {});
      }
      return;
    }
    if (!this.followupInput.down) { return; }
    this.resources.deferPrefetch();
    if (this.followupInput.move(point.windowX, point.windowY)) {
      this.dragOffset = this.followupInput.gap - (this.continuationIncoming ? this.dragSide * this.surfaceWidth : 0);
      this.continuationFraction = this.followupInput.content / Math.max(1, this.surfaceWidth);
      this.sendContinuationMove();
    }
    if (event.type === TouchType.Up) {
      const delta = this.followupInput.finish(point.windowX, point.windowY);
      this.finishContinuation(delta);
    }
  }
  private sendContinuationMove(): void {
    if (this.continuationMoveBusy || this.continuationSlot < 0) { return; }
    const version = this.continuationMoveVersion;
    const fraction = this.continuationFraction;
    this.continuationMoveBusy = true;
    this.controllers[this.continuationSlot].runJavaScript('window.ReadBooks.externalMove(' + fraction + ')').catch(() => {}).then(() => {
      if (version !== this.continuationMoveVersion) { return; }
      this.continuationMoveBusy = false;
      if (this.followupInput.down && fraction !== this.continuationFraction) { this.sendContinuationMove(); }
    });
  }
  private finishContinuation(delta: number): void {
    if (this.continuationSlot < 0) { return; }
    const id = this.continuationSlot;
    const slot = this.pool.slots[id];
    const outside = slot.page + delta < 0 || slot.page + delta >= slot.pages;
    const crossesPair = outside && delta === (this.continuationIncoming ? -this.drag.delta : this.drag.delta);
    const commit = crossesPair ? !this.continuationIncoming : this.continuationIncoming;
    const advance = outside ? 0 : delta;
    const carry = outside && !crossesPair ? delta : 0;
    const destination = commit ? -this.dragSide * this.surfaceWidth : 0;
    const bodyDistance = (slot.rtl ? 1 : -1) * advance * this.surfaceWidth - this.followupInput.content;
    const motion = pageSettle(destination - this.dragOffset + bodyDistance, this.surfaceWidth, this.followupInput.velocity.value);
    if (this.settings.reduceMotion) { motion.duration = 0; }
    this.continuationMoveVersion++; this.continuationMoveBusy = false;
    this.dragSettling = true; this.settleCommits = commit;
    const epoch = this.dragEpoch;
    const command = 'window.ReadBooks.externalMove(' + this.continuationFraction + ');window.ReadBooks.externalFinish(' + advance + ',' + JSON.stringify(motion) + ');';
    // Start from the same last finger position. Native surface and inner page use
    // one duration/curve; no post-handoff go(N) jump and no queue of bridge moves.
    this.controllers[id].runJavaScript(command).then(() => {
      if (!this.active || epoch !== this.dragEpoch) { return; }
      this.animateTurn(destination, motion, () => this.completeTurn(commit, carry));
    }).catch(() => { if (epoch === this.dragEpoch) { this.resetDrag(); } });
  }
  private stopTurnAnimator(): void {
    this.dragEpoch++;
    const animation = this.turnAnimator; this.turnAnimator = null;
    if (animation !== null) {
      animation.onFrame = (_value: number): void => {};
      animation.onFinish = (): void => {};
      animation.onCancel = (): void => {};
      try { animation.cancel(); } catch (_) {}
    }
  }
  private animateTurn(destination: number, motion: PageSettle, finish: () => void): void {
    this.stopTurnAnimator();
    const epoch = this.dragEpoch;
    this.dragSettling = true;
    if (this.settings.reduceMotion || motion.duration <= 0) { this.dragOffset = destination; finish(); return; }
    const animation = this.getUIContext().createAnimator({ duration: motion.duration,
      easing: 'cubic-bezier(0.2,' + motion.firstY + ',0.55,1)', delay: 0, fill: 'forwards',
      direction: 'normal', iterations: 1, begin: this.dragOffset, end: destination });
    this.turnAnimator = animation;
    animation.setExpectedFrameRateRange(ReadingRefresh.range());
    animation.onFrame = (value: number): void => { if (this.active && epoch === this.dragEpoch) { this.dragOffset = value; } };
    animation.onFinish = (): void => {
      if (!this.active || epoch !== this.dragEpoch) { return; }
      this.dragOffset = destination; finish();
    };
    this.refresh.begin(false); animation.play();
  }
  private completeTurn(commit: boolean, carry: number = 0): void {
    if (!commit) {
      this.resetDrag();
      if (carry) { this.controller.runJavaScript('window.ReadBooks.go(' + carry + ')').catch(() => {}); }
      return;
    }
    const id = this.dragSlot;
    if (id < 0 || !this.pool.slots[id].ready) { this.resetDrag(); return; }
    this.save(); this.chapterStarted = Date.now(); this.generation++;
    this.dragCommit = true; this.pool.pending = id; this.pendingSeekDone = true;
    this.pendingLocator = null; this.pendingFragment = ''; this.queuedTurns = carry;
    // The continuation may already be displaying page 2. Do not seek back to page 1.
    this.finishPending(id);
  }
  private settleDrag(commit: boolean): void {
    if (!this.drag.boundary) { this.resetDrag(); return; }
    const delta = this.drag.delta;
    const target = this.sectionIndex + delta;
    if (target < 0 || target >= this.sections.length) { this.resetDrag(); return; }
    if (this.dragSlot < 0) {
      hilog.warn(0, 'ReadBooksEpubPerf', 'coldBoundary=%{public}d target=%{public}d', this.sectionIndex, target);
      const candidate = this.pool.find(this.sections[target].path);
      if (candidate >= 0) {
        const slot = this.pool.slots[candidate];
        hilog.warn(0, 'ReadBooksEpubPerf', 'coldState slot=%{public}d current=%{public}d pending=%{public}d ready=%{public}s page=%{public}d pages=%{public}d version=%{public}d expected=%{public}d',
          candidate, this.pool.current, this.pool.pending, slot.ready ? 'yes' : 'no', slot.page, slot.pages, slot.version, this.layoutVersion);
      } else { hilog.warn(0, 'ReadBooksEpubPerf', 'coldState slot=missing'); }
      this.resetDrag();
      if (commit) {
        const locator = new EpubLocator(); locator.path = this.sections[target].path; locator.fraction = delta < 0 ? 1 : 0;
        this.navigate(locator.path, '', locator);
      }
      return;
    }
    this.dragSettling = true;
    this.settleCommits = commit;
    this.controller.runJavaScript('window.ReadBooks.holdInput(true)').catch(() => {});
    const destination = commit ? -this.dragSide * this.surfaceWidth : 0;
    const motion = pageSettle(destination - this.dragOffset, this.surfaceWidth, this.drag.velocity.value);
    this.animateTurn(destination, motion, () => this.completeTurn(commit));
  }
  private currentBookmark(): Bookmark | undefined { return this.bookmarks.find((bookmark: Bookmark) => bookmark.charOffset === this.positionOffset()); }
  private async bookmark(): Promise<void> {
    if (!this.documentReady) { return; }
    try {
      const current = this.currentBookmark();
      if (current) { await BookmarkRepo.remove(current.id); }
      else { await BookmarkRepo.add(this.book.id, this.positionOffset(), this.sections[this.sectionIndex].title + ' · ' + (this.page + 1), JSON.stringify(this.locator)); }
      this.bookmarks = await BookmarkRepo.listByBook(this.book.id);
    } catch (_) { this.toast('书签保存失败'); }
  }
  private async removeBookmark(id: number): Promise<void> {
    try { await BookmarkRepo.remove(id); this.bookmarks = await BookmarkRepo.listByBook(this.book.id); }
    catch (_) { this.toast('未能删除书签'); }
  }
  private openBookmark(bookmark: Bookmark): void {
    try {
      const location = JSON.parse(bookmark.epubLocation) as EpubLocator;
      if (typeof location.path === 'string' && this.resources.has(location.path)) { this.navigate(location.path, '', location); }
      else { this.navigateOffset(bookmark.charOffset); }
    } catch (_) { this.navigateOffset(bookmark.charOffset); }
    this.panel = false;
  }

  private selectedEntry(item: EpubNavEntry): boolean {
    if (item.path !== this.path) { return false; }
    if (item.fragment) { try { return decodeURIComponent(item.fragment) === this.fragment; } catch (_) { return false; } }
    return !this.toc.some((entry: EpubNavEntry) => entry.path === this.path && entry.fragment === this.fragment);
  }

  private filterToc(): void {
    this.tocSource.update(this.toc.filter((item: EpubNavEntry) => item.title.toLowerCase().includes(this.query.trim().toLowerCase())));
  }
  private async finishBook(): Promise<void> {
    try { await ReadingActivityRepo.setFinished(this.book.id, true); this.toast('已标记为读完'); }
    catch (_) { this.toast('保存读完状态失败，请重试'); }
  }

  @Builder
  contents() {
    Column({ space: 12 }) {
      Row() {
        Text('目录与书签').fontSize(24).fontWeight(700).fontColor(this.palette().text).layoutWeight(1)
        IconButton({ icon: $r('app.media.ic_close'), label: '关闭目录', tint: this.palette().text, onAction: () => { this.panel = false; } })
      }.width('100%')
      Row({ space: 12 }) {
        Button('目录').id('epub_toc_tab').backgroundColor(this.bookmarkTab ? this.palette().bg : this.palette().edge)
          .fontColor(this.palette().text).onClick(() => { this.bookmarkTab = false; })
        Button('书签').id('epub_bookmark_tab').backgroundColor(this.bookmarkTab ? this.palette().edge : this.palette().bg)
          .fontColor(this.palette().text).onClick(() => { this.bookmarkTab = true; })
      }.width('100%')
      if (!this.bookmarkTab) {
        Search({ value: this.query, placeholder: '查找章节' }).id('epub_toc_search').fontColor(this.palette().text)
          .onChange((value: string) => { this.query = value; this.filterToc(); })
        List() {
          LazyForEach(this.tocSource, (item: EpubNavEntry, index: number) => {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
                Text(item.title).width('100%').fontSize(16).fontColor(this.palette().text).textAlign(TextAlign.Start)
                  .fontWeight(this.selectedEntry(item) ? 600 : 400).maxLines(3)
              }.id('epub_toc_' + index).width('100%').constraintSize({ minHeight: 52 }).padding({ left: 16 + Math.min(3, item.depth) * 16, right: 12, top: 14, bottom: 14 })
                .borderRadius(14).backgroundColor(this.selectedEntry(item) ? this.palette().edge : Color.Transparent)
                .onClick(() => { this.navigate(item.path, item.fragment); this.panel = false; })
            }
          }, (item: EpubNavEntry, index: number) => item.path + '#' + item.fragment + ':' + index)
        }.layoutWeight(1).width('100%')
      } else {
        if (!this.bookmarks.length) { Text('把想再读的页面，留在这里。').fontColor(this.palette().meta).padding(24) }
        List() {
          ForEach(this.bookmarks, (bookmark: Bookmark) => {
            ListItem() {
              Row() {
                Text(bookmark.excerpt).fontSize(16).fontColor(this.palette().text).maxLines(3).layoutWeight(1)
                  .padding(16).onClick(() => this.openBookmark(bookmark))
                IconButton({ icon: $r('app.media.ic_delete'), label: '删除书签', destructive: true, onAction: () => this.removeBookmark(bookmark.id) })
              }
            }
          }, (bookmark: Bookmark) => bookmark.id.toString())
        }.layoutWeight(1)
      }
      Button('标记为读完').fontColor(this.palette().text).backgroundColor(this.palette().edge).onClick(() => this.finishBook())
    }.padding(24).width('100%').height('100%').backgroundColor(this.palette().chrome)
  }
  @Builder
  sheet() {
    WithTheme({ colorMode: this.isNight() ? ThemeColorMode.DARK : ThemeColorMode.LIGHT }) {
      if (this.panelKind === 'settings') {
        ReadingSettingsPanel({ settings: this.settings, palette: this.palette(), wideWindow: this.wide, epub: true,
          fixedLayout: this.sections[this.sectionIndex]?.fixed ?? false,
          onFont: (delta: number) => { this.settings.publisherStyle = false; this.settings.fontSize = Math.max(17, Math.min(26, this.settings.fontSize + delta)); },
          onLineHeight: (delta: number) => { this.settings.publisherStyle = false; this.settings.lineHeight = Math.max(1.4, Math.min(2, this.settings.lineHeight + delta)); },
          onTheme: (theme: string) => { this.settings.theme = theme; },
          onLayoutMode: (mode: string) => { this.settings.layoutMode = mode; },
          onReduceMotion: (value: boolean) => { this.settings.reduceMotion = value; },
          onClose: () => { this.panel = false; } })
      } else { this.contents() }
    }
  }
  @Builder
  chapterSurface(id: number) {
    if (this.sources[id]) {
      Column() {
        Web({ src: this.sources[id], controller: this.controllers[id], incognitoMode: true, renderMode: RenderMode.ASYNC_RENDER })
          .id(this.hasPage && this.visibleSlot === id ? 'epub_web' : 'epub_prepared_' + id)
          .width('100%').height('100%').backgroundColor(Color.Transparent)
          .javaScriptAccess(true).fileAccess(false).domStorageAccess(false).databaseAccess(false)
          .onlineImageAccess(true).imageAccess(true).mixedMode(MixedMode.None).zoomAccess(false).overviewModeAccess(false)
          .darkMode(this.isNight() ? WebDarkMode.On : WebDarkMode.Off).forceDarkAccess(this.isNight())
          .onControllerAttached(() => { this.pool.slots[id].attached = true; })
          .onInterceptRequest((event) => this.resources.response(event.request.getRequestUrl(), this.pool.slots[id].path))
          .onLoadIntercept((event) => {
            try { return epubRequestPath(event.data.getRequestUrl(), this.resources.origin) !== this.pool.slots[id].path; } catch (_) { return true; }
          })
          .onPageEnd((event) => this.loadedSlot(id, event.url))
          .onConsole((event) => this.slotMessage(id, event.message.getMessage()))
          .onTouch((event: TouchEvent) => this.boundaryTouch(id, event))
      }.width('100%').height('100%')
        .padding({ left: 0, right: 0, top: 84, bottom: 120 }).clip(true)
        .translate({ x: this.surfaceX(id) })
        .opacity(this.hasPage && (this.visibleSlot === id || this.outgoingSlot === id || this.dragSlot === id) ? 1 : 0)
        .zIndex(this.visibleSlot === id ? 2 : this.outgoingSlot === id ? 1 : 0)
        .accessibilityLevel(this.hasPage && this.visibleSlot === id ? 'auto' : 'no-hide-descendants')
        .hitTestBehavior(this.hasPage && this.visibleSlot === id ? HitTestMode.Default : HitTestMode.None)
    }
  }
  build() {
    WithTheme({ colorMode: this.isNight() ? ThemeColorMode.DARK : ThemeColorMode.LIGHT }) {
      GridRow({ columns: 12, breakpoints: { value: ['1000vp'], reference: BreakpointsReference.WindowSize } }) {
        GridCol({ span: 12 }) {
          Stack() {
            if (this.settings.backgroundPath) {
              Image('file://' + this.settings.backgroundPath).width('100%').height('100%').objectFit(ImageFit.Cover)
                .opacity(this.settings.backgroundOpacity).hitTestBehavior(HitTestMode.None)
            }
            if (this.source) {
              this.chapterSurface(0)
              this.chapterSurface(1)
              this.chapterSurface(2)
              this.chapterSurface(3)
            }
            if (this.controls) {
              Column() {
                HudTopBar({ title: this.book.title, palette: this.palette(), bookmarked: this.currentBookmark() !== undefined,
                  onBack: () => this.back(), onBookmark: () => this.bookmark() })
                Blank()
                HudBottomBar({ palette: this.palette(), sliderValue: this.positionOffset() / Math.max(1, this.book.charCount - 1) * 1000,
                  progressLabel: (this.sectionIndex + 1) + ' / ' + this.sections.length + ' 章 · ' + (this.page + 1) + ' / ' + this.pages + ' 屏',
                  onSlider: (value: number, done: boolean) => { if (done) { this.navigateOffset(value / 1000 * (this.book.charCount - 1)); } },
                  onToc: () => this.openPanel('toc'), onSettings: () => this.openPanel('settings') })
              }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent).zIndex(3)
                .transition(ReaderMotion.reveal(this.settings.reduceMotion, 12))
            }
            if ((!this.hasPage && this.busy) || this.error) {
              Column({ space: 16 }) {
                if (this.error) {
                  Text(this.error).fontSize(18).fontColor(this.palette().text).textAlign(TextAlign.Center)
                  Button('返回书库').onClick(() => this.back())
                } else { LoadingProgress().width(32).height(32) }
              }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(32).backgroundColor(this.palette().bg).zIndex(4)
            }
          }.width('100%').height('100%').backgroundColor(this.palette().bg).clip(true)
            .onAreaChange((_old: Area, area: Area) => { this.surfaceWidth = Number(area.width); this.surfaceHeight = Number(area.height); })
            .onTouch((event: TouchEvent) => this.settleFollowup(event))
            .bindSheet($$this.panel, this.sheet(), { height: SheetSize.LARGE, dragBar: true, showClose: false,
              preferType: this.wide ? SheetType.CENTER : SheetType.BOTTOM, width: this.wide ? 560 : '100%',
              backgroundColor: this.palette().chrome, onDisappear: () => this.resume() })
        }.height('100%')
      }.width('100%').height('100%').onBreakpointChange((value: string) => { this.wide = value !== 'xs'; this.reflow(); })
    }
  }
}
