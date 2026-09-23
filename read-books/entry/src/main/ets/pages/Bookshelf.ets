import { iconTint, iconUsesStroke } from '../theme/IconTint';
import { router, mediaquery } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { Db } from '../data/Db';
import { BookRepo } from '../data/BookRepo';
import { ReadingActivityRepo, ReadingSummary } from '../data/ReadingActivityRepo';
import { ImportService, MAX_SOURCE_BYTES } from '../reader/ImportService';
import { BookImportService } from '../reader/BookImportService';
import { requireNativePdf } from '../reader/PdfCapability';
import { Book } from '../model/Models';
import { AppPreferences } from '../model/AppPreferences';
import { ReadingSettings } from '../model/ReadingSettings';
import { BookCard } from '../components/BookCard';
import { BookCover } from '../components/BookCover';
import { SuggestedBook } from '../components/SuggestedBook';
import { EmptyState } from '../components/EmptyState';
import { GlassNavigation } from '../components/GlassNavigation';
import { GoalProgress } from '../components/GoalProgress';
import { ReadingSettingsPanel } from '../components/ReadingSettingsPanel';
import { ShelfLayout } from '../theme/ShelfLayout';
import { ReaderMotion, LightFeedback } from '../theme/ReaderMotion';
import { NativeMaterial } from '../theme/NativeMaterial';
import { NativeShelfTabs } from '../components/NativeShelfTabs';
import { CoverService } from '../reader/CoverService';
import { BookSelection } from '../reader/BookSelection';
import { ProfileStore } from '../reader/ProfileStore';
import { ProfileAvatar } from '../components/ProfileAvatar';
import { CoverVisual } from '../reader/CoverVisual';
import { CoverColors } from '../theme/CoverColors';
import { ThemeManager } from '../theme/ThemeManager';
import { EpubSource } from '../reader/EpubSource';

@Entry
@ComponentV2
struct Bookshelf {
  @Local books: Book[] = [];
  @Local summary: ReadingSummary = new ReadingSummary();
  @Local selectedTab: string = 'home';
  @Local importing: boolean = false;
  @Local coverBusy: boolean = false;
  @Local importMessage: string = '';
  @Local ready: boolean = false;
  @Local loading: boolean = false;
  @Local loadError: string = '';
  @Local searchVisible: boolean = false;
  @Local query: string = '';
  @Local libraryFilter: string = 'all';
  @Local sheetVisible: boolean = false;
  @Local sheetKind: string = 'goals';
  @Local selectedBook: Book = new Book();
  @Local windowWidth: number = 390;
  @Local profileName: string = '';
  @Local profileBusy: boolean = false;
  @Local featuredTone: string = '#677D91';
  @Local featuredRatio: number = 0.66;
  @Local systemDark: boolean = false;
  private darkListener: mediaquery.MediaQueryListener | null = null;
  preferences: AppPreferences = AppPreferences.load();
  readingSettings: ReadingSettings = ReadingSettings.load();
  private opening: boolean = false;
  private reloadVersion: number = 0;
  private scroller: Scroller = new Scroller();
  private searchController: SearchController = new SearchController();
  private nativeTabs: boolean = NativeMaterial.supported();
  private libraryScroller: Scroller = new Scroller();
  private profileScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.darkListener = mediaquery.matchMediaSync('(prefers-color-scheme: dark)');
    this.systemDark = this.darkListener.matches;
    this.darkListener.on('change', (value: mediaquery.MediaQueryResult) => { this.systemDark = value.matches; });
    this.applyAppearance();
    this.bootstrap();
  }

  aboutToDisappear(): void { this.darkListener?.off('change'); }

  pageTransition() {
    PageTransitionExit(ReaderMotion.pageEnter(this.readingSettings.reduceMotion))
      .opacity(this.readingSettings.reduceMotion ? 1 : 0.92)
      .scale({ x: this.readingSettings.reduceMotion ? 1 : 0.985, y: this.readingSettings.reduceMotion ? 1 : 0.985 })
    PageTransitionEnter(ReaderMotion.pageExit(this.readingSettings.reduceMotion))
      .opacity(this.readingSettings.reduceMotion ? 1 : 0.92)
      .scale({ x: this.readingSettings.reduceMotion ? 1 : 0.985, y: this.readingSettings.reduceMotion ? 1 : 0.985 })
  }

  onPageShow(): void {
    if (this.ready && !this.importing && !this.coverBusy) {
      this.refresh();
    }
  }

  onBackPress(): boolean {
    if (this.sheetVisible) {
      this.sheetVisible = false;
      return true;
    }
    if (this.searchVisible) {
      this.searchVisible = false;
      this.query = '';
      return true;
    }
    if (this.selectedTab !== 'home') {
      this.selectTab('home');
      return true;
    }
    return false;
  }

  private async bootstrap(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.loadError = '';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await Db.init(context);
      await ImportService.recover(context);
      // A new installation starts empty; only the user's imports populate the library.
      await this.reload();
      this.ready = true;
      CoverService.repairMissingPdfs(context, this.books, async () => { await this.reload(); });
    } catch (e) {
      this.loadError = '暂时无法读取本地图书，请重试。';
    } finally {
      this.loading = false;
    }
  }

  private async reload(): Promise<void> {
    const version: number = ++this.reloadVersion;
    const books: Book[] = await BookRepo.listAll();
    const summary: ReadingSummary = await ReadingActivityRepo.summary(this.preferences.dailyMinutes);
    if (version === this.reloadVersion) {
      this.books = books;
      this.summary = summary;
      this.loadError = '';
      const featured: Book = this.featured();
      CoverVisual.read(featured).then((visual) => {
        if (version === this.reloadVersion && featured.id === this.featured().id) {
          this.featuredTone = visual.tone;
          this.featuredRatio = Math.max(0.35, Math.min(2, visual.ratio));
        }
      });
    }
  }

  private async refresh(): Promise<void> {
    try {
      await this.reload();
    } catch (e) {
      this.loadError = '更新失败，请重试。';
      this.toast(this.loadError);
    }
  }

  private applyAppearance(): void {
    const mode: ConfigurationConstant.ColorMode = this.preferences.appearance === 'dark' ?
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK : this.preferences.appearance === 'light' ?
        ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    (getContext(this) as common.UIAbilityContext).getApplicationContext().setColorMode(mode);
  }

  private selectTab(tab: string): void {
    if (tab === this.selectedTab && !this.searchVisible) { return; }
    if (!this.nativeTabs) { this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); }
    this.getUIContext().animateTo(ReaderMotion.change(this.readingSettings.reduceMotion), () => {
      this.selectedTab = tab;
      this.searchVisible = false;
      this.query = '';
    });
  }

  private wide(): boolean { return this.windowWidth >= ShelfLayout.WIDE; }
  private inset(): number { return ShelfLayout.inset(this.windowWidth); }
  private featured(): Book { return BookSelection.featured(this.books, this.summary.finishedIds); }

  private search(): void {
    this.selectTab('library');
    this.libraryFilter = 'all';
    this.searchVisible = true;
  }

  private showSheet(kind: string): void {
    if (kind === 'profile') { this.profileName = this.preferences.username; }
    this.sheetKind = kind;
    this.sheetVisible = true;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500 });
  }

  private isFinished(book: Book): boolean {
    return this.summary.finishedIds.indexOf(book.id) >= 0;
  }

  private displayBooks(): Book[] {
    const query: string = this.query.trim().toLocaleLowerCase();
    const books: Book[] = this.books.filter((book: Book) =>
      (query.length === 0 || (book.title + ' ' + book.author).toLocaleLowerCase().indexOf(query) >= 0) &&
      (this.libraryFilter === 'all' || (this.libraryFilter === 'finished' ? this.isFinished(book) :
        !this.isFinished(book) && book.lastReadAt > 0)));
    if (this.preferences.librarySort === 'title') {
      books.sort((left: Book, right: Book) => left.title.localeCompare(right.title));
    } else if (this.preferences.librarySort === 'added') {
      books.sort((left: Book, right: Book) => right.createdAt - left.createdAt);
    }
    return books;
  }

  private recentBooks(): Book[] {
    return BookSelection.recent(this.books, this.summary.finishedIds).slice(0, 8);
  }

  private yearBooks(): Book[] {
    return this.books.filter((book: Book) => this.summary.yearFinishedIds.indexOf(book.id) >= 0);
  }

  private async openBook(book: Book): Promise<void> {
    if (this.opening) {
      return;
    }
    this.opening = true;
    try {
      const current = await BookRepo.getById(book.id);
      if (current === null) { this.toast('这本书已不在书库中'); return; }
      if (current.format === 'epub' && !current.sourcePath) {
        AlertDialog.show({ title: '补全这本书的图文',
          message: '旧版仅保留了文字，所以插图与原排版无法显示。请重新选择同一本 EPUB 原文件一次；不会新增重复图书，阅读位置和书签会保留。',
          primaryButton: { value: '暂不打开', action: () => {} },
          secondaryButton: { value: '选择原文件', action: () => { this.completeEpub(current, true); } } });
        return;
      }
      if (book.format === 'pdf') { requireNativePdf(); }
      const params: Record<string, Object> = { 'bookId': book.id };
      await router.pushUrl({ url: book.format === 'pdf' ? 'pages/PdfReader' :
        book.format === 'epub' ? 'pages/EpubReader' : 'pages/Reader', params: params });
    } catch (e) {
      this.toast(e instanceof Error ? e.message : '暂时无法打开图书，请重试');
    } finally {
      this.opening = false;
    }
  }

  private async pickAndImport(): Promise<void> {
    if (!this.ready || this.importing) {
      return;
    }
    this.importing = true;
    this.sheetVisible = false;
    this.importMessage = '正在选择文件';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 10;
      options.fileSuffixFilters = ['.txt', '.epub', '.pdf'];
      const files = await new picker.DocumentViewPicker(context).select(options);
      let succeeded: number = 0;
      let failed: number = 0;
      let error: string = '';
      let first: Book | null = null;
      for (let i: number = 0; i < files.length; i++) {
        this.importMessage = '正在导入 ' + (i + 1) + ' / ' + files.length;
        try {
          const book = await BookImportService.importFromUri(context, files[i]);
          first = first ?? book;
          succeeded++;
        } catch (e) {
          failed++;
          error = e instanceof Error ? e.message : '文件读取失败';
        }
      }
      await this.reload();
      if (first !== null) {
        this.selectTab('library');
        const book: Book = first;
        AlertDialog.show({ title: '已导入 ' + succeeded + ' 本图书',
          message: (failed > 0 ? failed + ' 本未完成：' + error + '\n' : '') + '现在开始阅读《' + book.title + '》？',
          primaryButton: { value: '稍后', action: () => {} },
          secondaryButton: { value: '立即阅读', action: () => { this.openBook(book); } } });
      } else if (failed > 0) {
        this.toast(error);
      }
    } catch (e) {
      this.toast(e instanceof Error ? e.message : '导入未完成');
    } finally {
      this.importing = false;
      this.importMessage = '';
    }
  }

  private manage(book: Book): void {
    this.selectedBook = book;
    this.showSheet('book');
  }

  private async markFinished(): Promise<void> {
    try {
      await ReadingActivityRepo.setFinished(this.selectedBook.id, !this.isFinished(this.selectedBook));
      await this.reload();
      this.sheetVisible = false;
    } catch (e) {
      this.toast('未能更新阅读状态，请重试');
    }
  }

  private async changeCover(kind: string): Promise<void> {
    if (this.coverBusy) { return; }
    const book: Book = this.selectedBook;
    this.coverBusy = true;
    this.sheetVisible = false;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      if (kind === 'pdf') { await CoverService.fromPdf(context, book); }
      else if (kind === 'text') { await CoverService.useText(context, book); }
      else {
        const options = new picker.DocumentSelectOptions();
        options.maxSelectNumber = 1;
        options.fileSuffixFilters = kind === 'epub' ? ['.epub'] : ['.jpg', '.jpeg', '.png'];
        const files = await new picker.DocumentViewPicker(context).select(options);
        if (files.length === 0) { return; }
        if (kind === 'epub') { await CoverService.fromEpub(context, book, files[0]); }
        else { await CoverService.fromImage(context, book, files[0]); }
      }
      await this.reload();
      this.toast('封面已更新');
    } catch (e) { this.toast(e instanceof Error ? e.message : '封面更新失败，请重试'); }
    finally { this.coverBusy = false; }
  }

  private confirmDelete(): void {
    const book = this.selectedBook;
    this.sheetVisible = false;
    AlertDialog.show({ title: '删除图书？',
      message: '删除《' + book.title + '》的本地副本、进度和书签。原文件仍会保留。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: $r('app.color.destructive'), action: () => { this.deleteBook(book); } } });
  }

  private async deleteBook(book: Book): Promise<void> {
    try {
      await ImportService.deleteBook(getContext(this) as common.UIAbilityContext, book);
      await ReadingActivityRepo.setFinished(book.id, false);
    } catch (e) {
      this.toast(e instanceof Error ? e.message : '删除未完成');
    } finally {
      await this.refresh();
    }
  }

  private async completeEpub(book: Book = this.selectedBook, openAfter: boolean = false): Promise<void> {
    if (this.importing || this.coverBusy) { return; }
    this.sheetVisible = false;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['EPUB 原文件|.epub'];
      const selected = await new picker.DocumentViewPicker(context).select(options);
      if (!selected.length) { return; }
      this.importing = true; this.importMessage = '正在补全原版图文，保留阅读记录';
      await EpubSource.attach(context, book, selected[0]);
      await this.reload(); this.toast('原版图文已补全，进度和书签已保留');
      if (openAfter) { await this.openBook(book); }
    } catch (e) { this.toast(e instanceof Error ? e.message : '未能补全 EPUB'); }
    finally { this.importing = false; }
  }

  @Builder
  circleButton(icon: Resource, label: string, id: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      Image(icon).width(24).height(24).fillColor(iconUsesStroke(icon) ? Color.Transparent : $r('app.color.label_primary'))
        .colorFilter(iconTint(this.getUIContext(), $r('app.color.label_primary')))
    }
    .width(44).height(44).padding(0).backgroundColor($r('app.color.glass_surface'))
    .border({ width: 0.5, color: $r('app.color.glass_edge') }).id(id).accessibilityText(label)
    .attributeModifier(new LightFeedback(this.readingSettings.reduceMotion))
    .onClick(() => action())
  }

  @Builder
  header(tab: string) {
    Row({ space: 12 }) {
      Text(tab === 'home' ? '主页' : tab === 'library' ? '书库' : '我的')
        .fontSize(this.wide() ? 42 : 34).fontWeight(700).fontColor($r('app.color.label_primary')).layoutWeight(1)
      if (this.wide() && tab === 'home') {
        Text('为阅读留一点时间。').fontSize(15).fontColor($r('app.color.label_secondary')).margin({ right: 16 })
      }
      if (tab === 'library') {
        this.circleButton($r('app.media.nav_search'), '搜索书库', 'library_search_button', () => this.search())
        this.circleButton(this.preferences.libraryLayout === 'grid' ? $r('app.media.nav_list') : $r('app.media.nav_grid'),
          '切换书库布局', 'library_layout', () => {
            this.getUIContext().animateTo(ReaderMotion.change(this.readingSettings.reduceMotion), () => {
              this.preferences.libraryLayout = this.preferences.libraryLayout === 'grid' ? 'list' : 'grid';
            });
          })
        this.circleButton($r('app.media.shelf_more'), '书库选项', 'library_more', () => this.showSheet('library'))
      }
    }.width('100%').height(this.wide() ? 112 : 94).padding({ left: this.inset(), right: this.inset(), top: 12, bottom: 12 })
  }

  @Builder
  bookRow(book: Book, card: boolean = false) {
    Row({ space: 14 }) {
      BookCover({ book: book, compact: true }).width(50).height(74)
      Column({ space: 4 }) {
        Text(book.title.replace('示例 · ', '')).fontSize(16).fontWeight(600).fontColor($r('app.color.label_primary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(book.author || (book.title.indexOf('西游记') >= 0 ? '吴承恩' : '未知作者'))
          .fontSize(14).fontColor($r('app.color.label_secondary')).maxLines(1)
        Text(this.isFinished(book) ? '已读完' : '图书 · ' + Math.floor(book.progressCharOffset / Math.max(1, book.charCount) * 100) + '%')
          .fontSize(13).fontColor($r('app.color.label_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.openBook(book))
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.shelf_more')).width(20).height(20).fillColor($r('app.color.label_secondary'))
      }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
        .attributeModifier(new LightFeedback(this.readingSettings.reduceMotion))
        .id('recent_manage_' + book.id).accessibilityText('管理《' + book.title + '》').onClick(() => this.manage(book))
    }
    .height(98).width('100%').padding({ left: card ? 12 : 0, right: card ? 2 : 0, top: 12, bottom: 12 })
    .backgroundColor(card ? $r('app.color.secondary_fill') : Color.Transparent).borderRadius(card ? 8 : 0)
    .attributeModifier(new LightFeedback(this.readingSettings.reduceMotion))
    .id('recent_book_' + book.id).accessibilityText('阅读《' + book.title + '》').onClick(() => this.openBook(book))
  }

  @Builder
  recentSection() {
    Column({ space: 18 }) {
      Row({ space: 4 }) {
        Text('接着读什么，' + this.preferences.username)
          .fontSize(23).fontWeight(700).fontColor($r('app.color.label_primary'))
        Blank()
        Button('查看全部', { type: ButtonType.Capsule }).fontSize(14).height(44)
          .fontColor($r('app.color.label_secondary')).backgroundColor(Color.Transparent)
          .attributeModifier(new LightFeedback(this.readingSettings.reduceMotion))
          .onClick(() => this.selectTab('library'))
      }.width('100%')
      if (this.books.length > 0) {
        Scroll() {
          Row({ space: this.wide() ? 28 : 20 }) {
            ForEach(BookSelection.suggestions(this.books, this.featured().id), (book: Book) => {
              SuggestedBook({ book: book, finished: this.isFinished(book), wide: this.wide(),
                reduced: this.readingSettings.reduceMotion, onOpen: () => this.openBook(book) })
            }, (book: Book) => book.id.toString())
          }.alignItems(VerticalAlign.Top).padding({ top: 8, bottom: 12 })
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
      } else {
        Button('导入第一本图书').height(48).fontColor($r('app.color.label_primary'))
          .backgroundColor($r('app.color.secondary_fill')).onClick(() => this.pickAndImport())
      }
    }.width('100%').padding({ bottom: 4 })
  }

  @Builder
  weekSection() {
    Column({ space: 14 }) {
      Row() {
        ForEach(['周日', '周一', '周二', '周三', '周四', '周五', '周六'], (label: string, index: number) => {
          Text(label).width(32).height(32).textAlign(TextAlign.Center).fontSize(12).fontWeight(600)
            .fontColor((this.summary.week[index]?.seconds ?? 0) >= this.preferences.dailyMinutes * 60 ?
              $r('app.color.goal_accent') : index === new Date().getDay() ?
                $r('app.color.label_primary') : $r('app.color.label_secondary'))
            .border({ width: 2, color: (this.summary.week[index]?.seconds ?? 0) >= this.preferences.dailyMinutes * 60 ?
              $r('app.color.goal_accent') : $r('app.color.separator') }).borderRadius(16)
        })
      }.width('100%').justifyContent(FlexAlign.SpaceBetween)
      Column({ space: 4 }) {
        Text(this.summary.streak > 0 ? '已连续阅读 ' + this.summary.streak + ' 天' : '开启连续阅读新记录')
          .fontSize(16).fontWeight(600).fontColor($r('app.color.label_primary'))
        Text(this.summary.bestStreak > 0 ? '你的记录是 ' + this.summary.bestStreak + ' 天。' : '今天，从一页开始。')
          .fontSize(14).fontColor($r('app.color.label_secondary'))
      }
    }.width('100%').padding({ top: 14, bottom: 4 })
  }

  @Builder
  yearlySection() {
    Row({ space: 24 }) {
      Column({ space: 12 }) {
        Text('这一年，读到更多').fontSize(23).fontWeight(700).fontColor($r('app.color.label_primary'))
        Text('已读 ' + this.summary.yearFinishedIds.length + ' 本 · 年度目标 ' + this.preferences.yearlyBooks + ' 本')
          .fontSize(14).fontColor($r('app.color.label_secondary'))
        Progress({ value: Math.min(this.preferences.yearlyBooks, this.summary.yearFinishedIds.length),
          total: this.preferences.yearlyBooks, type: ProgressType.Linear })
          .width('100%').constraintSize({ maxWidth: 360 }).color($r('app.color.goal_accent'))
          .backgroundColor($r('app.color.separator')).style({ strokeWidth: 4 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.wide()) {
        Row({ space: 12 }) {
          ForEach([0, 1, 2, 3, 4], (index: number) => {
            Stack() {
              if (index < this.yearBooks().length) {
                BookCover({ book: this.yearBooks()[index], compact: true })
              } else {
                Text((index + 1).toString()).fontSize(22).fontColor($r('app.color.label_tertiary'))
              }
            }.width(54).height(80).backgroundColor($r('app.color.secondary_fill')).borderRadius(4)
          })
        }
      }
      Image($r('app.media.nav_chevron')).width(18).height(18)
        .colorFilter(iconTint(this.getUIContext(), $r('app.color.label_secondary')))
    }.width('100%').padding(24).backgroundColor($r('app.color.surface')).borderRadius(22)
      .border({ width: 0.75, color: $r('app.color.card_edge') })
      .attributeModifier(new LightFeedback(this.readingSettings.reduceMotion))
      .id('year_goal').accessibilityText('年度阅读目标，已读 ' + this.summary.yearFinishedIds.length + ' 本')
      .onClick(() => this.showSheet('goals'))
  }

  @Builder
  goalPanel() {
    Column({ space: 6 }) {
      Row() {
        Text('阅读目标').fontSize(19).fontWeight(700).fontColor($r('app.color.label_primary'))
        Blank()
        Text('每天一点').fontSize(12).fontColor($r('app.color.label_secondary'))
      }.width('100%')
      GoalProgress({ seconds: this.summary.todaySeconds, minutes: this.preferences.dailyMinutes,
        reduceMotion: this.readingSettings.reduceMotion, onEdit: () => this.showSheet('goals') })
        .margin({ top: 8, bottom: 2 })
      this.weekSection()
    }.width('100%').height(348).padding(24).borderRadius(24).backgroundColor($r('app.color.surface'))
      .border({ width: 0.75, color: $r('app.color.card_edge') }).id('home_goal_panel')
  }

  @Builder
  featuredBook() {
    Row({ space: this.wide() ? 28 : 18 }) {
      Column({ space: 12 }) {
        Text(this.featured().lastReadAt > 0 && !this.isFinished(this.featured()) ? '继续阅读，' + this.preferences.username : '接着读什么，' + this.preferences.username)
          .fontSize(14).fontWeight(600).fontColor($r('app.color.label_secondary'))
        Text(this.books.length > 0 ? this.featured().title.replace('示例 · ', '') : '下一段故事，\n从这里开始。')
          .fontSize(this.windowWidth >= 1100 ? 34 : 26).fontWeight(700).lineHeight(this.windowWidth >= 1100 ? 43 : 34)
          .fontColor($r('app.color.label_primary')).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.books.length > 0 ? this.featured().author || (this.featured().title.indexOf('西游记') >= 0 ? '吴承恩' : '本地图书') : '导入 TXT、EPUB 或 PDF')
          .fontSize(15).fontColor($r('app.color.label_secondary')).maxLines(1)
        Blank()
        if (this.books.length > 0) {
          Text(this.featured().format.toUpperCase() + ' · 已读 ' + Math.floor(this.featured().progressCharOffset / Math.max(1, this.featured().charCount) * 100) + '%')
            .fontSize(13).fontColor($r('app.color.label_secondary'))
        }
        Button(this.books.length > 0 ? this.featured().lastReadAt > 0 && !this.isFinished(this.featured()) ? '继续阅读' : '开始阅读' : '导入图书', { type: ButtonType.Capsule })
          .height(46).padding({ left: 24, right: 24 }).fontSize(16).fontWeight(600)
          .fontColor($r('app.color.background')).backgroundColor($r('app.color.label_primary'))
          .attributeModifier(new LightFeedback(this.readingSettings.reduceMotion))
          .id('home_continue').onClick(() => { if (this.books.length > 0) { this.openBook(this.featured()); } else { this.pickAndImport(); } })
      }.layoutWeight(1).height('100%').alignItems(HorizontalAlign.Start)
      if (this.books.length > 0) {
        Button({ type: ButtonType.Normal }) { BookCover({ book: this.featured() }) }
          .width(this.windowWidth >= 1100 ? 178 : this.wide() ? 136 : 104)
          .aspectRatio(this.featuredRatio).constraintSize({ maxHeight: this.wide() ? 284 : 246 })
          .padding(0).borderRadius(5).backgroundColor(Color.Transparent)
          .shadow({ radius: 22, color: '#46000000', offsetY: 14 })
          .rotate({ angle: 5 }).attributeModifier(new LightFeedback(this.readingSettings.reduceMotion))
          .accessibilityText('阅读《' + this.featured().title + '》').onClick(() => this.openBook(this.featured()))
      }
    }.width('100%').height(this.wide() ? 348 : 310).padding(this.wide() ? 32 : 24).borderRadius(24)
      .linearGradient({ angle: 120, colors: [[CoverColors.surface(this.featuredTone, ThemeManager.effectiveDark(this.preferences.appearance, this.systemDark)), 0],
        [CoverColors.surface(this.featuredTone, ThemeManager.effectiveDark(this.preferences.appearance, this.systemDark), true), 1]] })
      .border({ width: 0.75, color: $r('app.color.card_edge') }).id('home_featured')
  }

  @Builder
  homeContent() {
    Column({ space: this.wide() ? 28 : 24 }) {
      if (this.wide()) {
        Row({ space: 24 }) {
          Column() { this.featuredBook() }.layoutWeight(1)
          Column() { this.goalPanel() }.width(this.windowWidth >= 1100 ? 328 : 292)
        }.width('100%').alignItems(VerticalAlign.Top).id('home_wide_layout')
      } else {
        this.featuredBook()
      }
      if (this.books.length > 1) { this.recentSection() }
      if (!this.wide()) { this.goalPanel() }
      this.yearlySection()
    }.width('100%').padding({ left: this.inset(), right: this.inset(), bottom: 24 })
  }

  @Builder
  filter(key: string, label: string) {
    Text(label).fontSize(14).fontWeight(this.libraryFilter === key ? 600 : 400)
      .fontColor(this.libraryFilter === key ? $r('app.color.label_primary') : $r('app.color.label_secondary'))
      .height(44).padding({ left: 14, right: 14 }).textAlign(TextAlign.Center)
      .border({ width: { bottom: this.libraryFilter === key ? 2 : 0 }, color: $r('app.color.label_primary') })
      .animation(ReaderMotion.change(this.readingSettings.reduceMotion))
      .attributeModifier(new LightFeedback(this.readingSettings.reduceMotion))
      .id('filter_' + key).onClick(() => {
        this.getUIContext().animateTo(ReaderMotion.change(this.readingSettings.reduceMotion), () => { this.libraryFilter = key; });
      })
  }

  @Builder
  libraryContent() {
    Column({ space: 18 }) {
      if (this.searchVisible) {
        Search({ value: this.query, placeholder: '搜索书名或作者', controller: this.searchController })
          .height(48).backgroundColor($r('app.color.secondary_fill')).fontColor($r('app.color.label_primary'))
          .id('library_search').onChange((value: string) => { this.query = value; })
          .transition(ReaderMotion.reveal(this.readingSettings.reduceMotion, -8))
      }
      Row() {
        this.filter('all', '全部')
        this.filter('reading', '在读')
        this.filter('finished', '已读完')
        Blank()
        Text(this.displayBooks().length + ' 本').fontSize(13).fontColor($r('app.color.label_secondary'))
      }.width('100%')
      if (this.displayBooks().length === 0) {
        if (this.query.length > 0 || this.libraryFilter !== 'all') {
          Column({ space: 12 }) {
            Image($r('app.media.nav_search')).width(32).height(32).colorFilter(iconTint(this.getUIContext(), $r('app.color.label_secondary')))
            Text(this.query.length > 0 ? '没有找到相关图书' : this.libraryFilter === 'finished' ? '还没有读完的图书' : '还没有正在阅读的图书')
              .fontSize(17).fontColor($r('app.color.label_secondary')).textAlign(TextAlign.Center)
          }.width('100%').padding({ top: 70, bottom: 70 })
        } else {
          EmptyState({ actionEnabled: !this.importing, onImport: () => { this.pickAndImport(); } })
        }
      } else if (this.preferences.libraryLayout === 'list') {
        Column() {
          ForEach(this.displayBooks(), (book: Book) => {
            this.bookRow(book)
            Divider().color($r('app.color.separator'))
          }, (book: Book) => book.id.toString())
        }.width('100%').transition(ReaderMotion.reveal(this.readingSettings.reduceMotion))
      } else {
        GridRow({ columns: ShelfLayout.columns(this.windowWidth), gutter: { x: 24, y: 24 } }) {
          ForEach(this.displayBooks(), (book: Book) => {
            GridCol({ span: 1 }) {
              BookCard({ book: book, finished: this.isFinished(book), onOpen: () => { this.openBook(book); },
                onDelete: () => this.manage(book) })
            }
          }, (book: Book) => book.id.toString())
        }.width('100%').transition(ReaderMotion.reveal(this.readingSettings.reduceMotion))
      }
    }.width('100%').padding({ left: this.inset(), right: this.inset(), top: 8, bottom: 32 })
  }

  @Builder
  settingsRow(icon: Resource, title: string, value: () => string, action: () => void) {
    Row({ space: 14 }) {
      Image(icon).width(23).height(23).colorFilter(iconTint(this.getUIContext(), $r('app.color.label_primary')))
      Text(title).fontSize(16).fontColor($r('app.color.label_primary')).layoutWeight(1)
      Text(value()).fontSize(14).fontColor($r('app.color.label_secondary')).maxLines(1)
      Image($r('app.media.nav_chevron')).width(16).height(16).colorFilter(iconTint(this.getUIContext(), $r('app.color.label_secondary')))
    }.width('100%').height(62).borderRadius(12).accessibilityGroup(true).accessibilityText(title + '，' + value())
      .attributeModifier(new LightFeedback(this.readingSettings.reduceMotion)).onClick(() => action())
  }

  private async chooseAvatar(): Promise<void> {
    if (this.profileBusy) { return; }
    this.profileBusy = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['图片|.png,.jpg,.jpeg'];
      const selected = await new picker.DocumentViewPicker(context).select(options);
      if (selected.length > 0) { await ProfileStore.replaceAvatar(context, selected[0], this.preferences); }
    } catch (e) { this.toast(e instanceof Error ? e.message : '头像未能保存，请换一张图片重试'); }
    finally { this.profileBusy = false; }
  }

  @Builder
  profileEditor() {
    Column({ space: 24 }) {
      Row() {
        Text('个人资料').fontSize(23).fontWeight(700).fontColor($r('app.color.label_primary')).layoutWeight(1)
        this.circleButton($r('app.media.ic_close'), '关闭', 'sheet_close', () => { this.sheetVisible = false; })
      }.width('100%')
      Button({ type: ButtonType.Circle }) { ProfileAvatar({ path: this.preferences.avatarPath, diameter: 88 }) }
        .width(88).height(88).padding(0).backgroundColor(Color.Transparent).enabled(!this.profileBusy)
        .id('profile_choose_avatar').accessibilityText('选择头像').onClick(() => this.chooseAvatar())
      Text(this.profileBusy ? '正在保存头像…' : '轻点更换头像').fontSize(13).fontColor($r('app.color.label_secondary'))
      TextInput({ text: this.profileName, placeholder: '怎么称呼你' }).maxLength(20).height(54)
        .fontSize(18).backgroundColor($r('app.color.secondary_fill')).borderRadius(16)
        .id('profile_name').accessibilityText('用户名').onChange((name: string) => { this.profileName = name; })
      Button('保存', { type: ButtonType.Capsule }).width('100%').height(48)
        .fontSize(17).fontWeight(600).backgroundColor($r('app.color.label_primary')).fontColor($r('app.color.background'))
        .id('profile_save').enabled(!this.profileBusy).onClick(() => {
          this.preferences.username = AppPreferences.cleanName(this.profileName);
          this.sheetVisible = false;
        })
      Text('头像与用户名仅保存在这台设备，不会上传。').fontSize(12).fontColor($r('app.color.label_secondary'))
    }.width('100%').padding(24)
  }

  @Builder
  profileSummary() {
    Column({ space: 0 }) {
      Row({ space: 18 }) {
        Button({ type: ButtonType.Circle }) { ProfileAvatar({ path: this.preferences.avatarPath }) }
          .width(68).height(68).padding(0).backgroundColor(Color.Transparent).id('profile_avatar')
          .accessibilityText('编辑头像与用户名').onClick(() => this.showSheet('profile'))
        Column({ space: 7 }) {
          Text(this.preferences.username).fontSize(25).fontWeight(700).fontColor($r('app.color.label_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('我的阅读').fontSize(13).fontColor($r('app.color.label_secondary'))
          Text(this.books.length + ' 本图书 · ' + this.summary.readingDays + ' 个阅读日')
            .fontSize(14).fontColor($r('app.color.label_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.showSheet('profile'))
      }.width('100%').padding({ top: 20, bottom: 36 })
      Row() {
        this.stat( () => Math.floor(this.summary.totalSeconds / 60).toString(), '累计分钟')
        this.stat( () => this.summary.finishedIds.length.toString(), '已读图书')
        this.stat( () => this.summary.bestStreak.toString(), '最长连续天数')
      }.width('100%').padding({ bottom: 36 })
    }.width('100%').padding({ left: 24, right: 24, top: 8 }).borderRadius(24)
      .backgroundColor($r('app.color.surface')).border({ width: 0.75, color: $r('app.color.card_edge') })
  }

  @Builder
  profileSettings() {
    Column() {
      this.settingsRow($r('app.media.nav_target'), '阅读目标', () => this.preferences.dailyMinutes + ' 分钟 / 天', () => this.showSheet('goals'))
      Divider().color($r('app.color.separator')).margin({ left: 37 })
      this.settingsRow($r('app.media.nav_moon'), '外观', () => this.preferences.appearance === 'dark' ? '深色' :
        this.preferences.appearance === 'light' ? '浅色' : '跟随系统', () => this.showSheet('appearance'))
      Divider().color($r('app.color.separator')).margin({ left: 37 })
      this.settingsRow($r('app.media.nav_book'), '阅读设置', () => '', () => this.showSheet('reading'))
      Divider().color($r('app.color.separator')).margin({ left: 37 })
      this.settingsRow($r('app.media.nav_info'), '关于与本地数据', () => '', () => this.showSheet('about'))
    }.width('100%').padding({ left: 24, right: 24, top: 8, bottom: 8 }).borderRadius(24)
      .backgroundColor($r('app.color.surface')).border({ width: 0.75, color: $r('app.color.card_edge') })
  }

  @Builder
  profileContent() {
    Column({ space: 24 }) {
      if (this.wide()) {
        Row({ space: 28 }) {
          Column({ space: 24 }) {
            this.profileSummary()
          }.layoutWeight(4)
          Column() { this.profileSettings() }.layoutWeight(6)
        }.width('100%').alignItems(VerticalAlign.Top).id('profile_wide_layout')
      } else {
        this.profileSummary()
        this.profileSettings()
      }
      Text('READ BOOKS').fontFamily('DM Sans').fontSize(13).fontWeight(600)
        .fontColor($r('app.color.label_secondary')).padding({ top: 42, bottom: 8 })
      Text('让阅读回到阅读。').fontSize(13).fontColor($r('app.color.label_secondary'))
    }.width('100%').padding({ left: this.inset(), right: this.inset(), bottom: 40 })
  }

  @Builder
  stat(value: () => string, label: string) {
    Column({ space: 8 }) {
      Text(value()).fontFamily('DM Sans').fontSize(28).fontWeight(600).fontColor($r('app.color.label_primary'))
      Text(label).fontSize(12).fontColor($r('app.color.label_secondary')).maxLines(1)
    }.layoutWeight(1)
  }

  @Builder
  goalStepper(label: string, value: () => number, suffix: string, min: number, max: number, update: (delta: number) => void) {
    Column({ space: 18 }) {
      Text(label).fontSize(17).fontWeight(600).fontColor($r('app.color.label_primary'))
      Row({ space: 20 }) {
        Button('−', { type: ButtonType.Circle }).width(48).height(48).fontSize(24)
          .backgroundColor($r('app.color.secondary_fill')).fontColor($r('app.color.label_primary'))
          .attributeModifier(new LightFeedback(this.readingSettings.reduceMotion))
          .enabled(value() > min).accessibilityText('减少' + label).onClick(() => update(-1))
        Text(value() + suffix).fontSize(26).fontWeight(600).fontColor($r('app.color.label_primary'))
          .width(140).textAlign(TextAlign.Center)
        Button('+', { type: ButtonType.Circle }).width(48).height(48).fontSize(24)
          .backgroundColor($r('app.color.secondary_fill')).fontColor($r('app.color.label_primary'))
          .attributeModifier(new LightFeedback(this.readingSettings.reduceMotion))
          .enabled(value() < max).accessibilityText('增加' + label).onClick(() => update(1))
      }.justifyContent(FlexAlign.Center).width('100%')
    }.width('100%').padding({ top: 24, bottom: 24 })
  }

  @Builder
  sheetAction(label: string, selected: () => boolean, action: () => void) {
    Row() {
      Text(label).fontSize(17).fontColor($r('app.color.label_primary')).layoutWeight(1)
      if (selected()) {
        Image($r('app.media.nav_check')).width(22).height(22).colorFilter(iconTint(this.getUIContext(), $r('app.color.goal_accent')))
      }
    }.width('100%').height(56).borderRadius(12).id('sheet_action_' + label)
      .accessibilityText(label + (selected() ? '，已选择' : ''))
      .attributeModifier(new LightFeedback(this.readingSettings.reduceMotion)).onClick(() => action())
    Divider().color($r('app.color.separator'))
  }

  @Builder
  sheetContent() {
    if (this.sheetKind === 'profile') {
      this.profileEditor()
    } else if (this.sheetKind === 'reading') {
      ReadingSettingsPanel({ settings: this.readingSettings, wideWindow: this.windowWidth >= 1000,
        palette: ThemeManager.resolve(this.readingSettings.theme, this.systemDark, this.preferences.appearance),
        onFont: (delta: number) => { this.readingSettings.fontSize = Math.max(17, Math.min(26, this.readingSettings.fontSize + delta)); },
        onLineHeight: (delta: number) => { this.readingSettings.lineHeight = Math.max(1.4, Math.min(2, Math.round((this.readingSettings.lineHeight + delta) * 100) / 100)); },
        onTheme: (theme: string) => { this.readingSettings.theme = theme; },
        onLayoutMode: (mode: string) => { this.readingSettings.layoutMode = mode; },
        onReduceMotion: (value: boolean) => { this.readingSettings.reduceMotion = value; },
        onClose: () => { this.sheetVisible = false; } })
    } else {
      Column() {
        Row() {
          Text(this.sheetKind === 'goals' ? '阅读目标' : this.sheetKind === 'appearance' ? '外观' :
            this.sheetKind === 'book' ? '图书选项' : this.sheetKind === 'about' ? '关于 READ BOOKS' : '书库选项')
            .fontSize(23).fontWeight(700).fontColor($r('app.color.label_primary')).layoutWeight(1)
          this.circleButton($r('app.media.ic_close'), '关闭', 'sheet_close', () => { this.sheetVisible = false; })
        }.width('100%').padding({ bottom: 20 })
        if (this.sheetKind === 'goals') {
          this.goalStepper('每日阅读', () => this.preferences.dailyMinutes, ' 分钟', 5, 240, (delta: number) => {
            this.preferences.dailyMinutes = Math.max(5, Math.min(240, this.preferences.dailyMinutes + delta * 5));
            this.refresh();
          })
          Divider().color($r('app.color.separator'))
          this.goalStepper('年度图书', () => this.preferences.yearlyBooks, ' 本', 1, 100, (delta: number) => {
            this.preferences.yearlyBooks = Math.max(1, Math.min(100, this.preferences.yearlyBooks + delta));
          })
        } else if (this.sheetKind === 'appearance') {
          this.sheetAction('跟随系统', () => this.preferences.appearance === 'system', () => { this.preferences.appearance = 'system'; this.applyAppearance(); })
          this.sheetAction('浅色', () => this.preferences.appearance === 'light', () => { this.preferences.appearance = 'light'; this.applyAppearance(); })
          this.sheetAction('深色', () => this.preferences.appearance === 'dark', () => { this.preferences.appearance = 'dark'; this.applyAppearance(); })
        } else if (this.sheetKind === 'library') {
          this.sheetAction('导入图书', () => false, () => { this.pickAndImport(); })
          this.sheetAction('最近阅读', () => this.preferences.librarySort === 'recent', () => { this.preferences.librarySort = 'recent'; this.sheetVisible = false; })
          this.sheetAction('书名排序', () => this.preferences.librarySort === 'title', () => { this.preferences.librarySort = 'title'; this.sheetVisible = false; })
          this.sheetAction('最近添加', () => this.preferences.librarySort === 'added', () => { this.preferences.librarySort = 'added'; this.sheetVisible = false; })
        } else if (this.sheetKind === 'book') {
          Text(this.selectedBook.title).fontSize(17).fontColor($r('app.color.label_secondary')).maxLines(3)
            .width('100%').margin({ bottom: 16 })
          this.sheetAction('开始阅读', () => false, () => { this.sheetVisible = false; this.openBook(this.selectedBook); })
          this.sheetAction(this.isFinished(this.selectedBook) ? '标记为未读完' : '标记为已读完', () => this.isFinished(this.selectedBook), () => { this.markFinished(); })
          this.sheetAction('更换封面', () => false, () => { this.changeCover('image'); })
          if (this.selectedBook.format === 'epub') {
            if (!this.selectedBook.sourcePath) {
              this.sheetAction('补全原版图文（保留进度）', () => false, () => { this.completeEpub(); })
            }
            this.sheetAction('从 EPUB 原文件恢复封面', () => false, () => { this.changeCover('epub'); })
          } else if (this.selectedBook.format === 'pdf') {
            this.sheetAction('重新生成首页封面', () => false, () => { this.changeCover('pdf'); })
          }
          if (this.selectedBook.format === 'txt' && this.selectedBook.coverPath.length > 0) {
            this.sheetAction('使用文字封面', () => false, () => { this.changeCover('text'); })
          }
          this.sheetAction('删除图书', () => false, () => this.confirmDelete())
        } else {
          Text('READ BOOKS 0.2.1').fontSize(24).fontWeight(600).fontColor($r('app.color.label_primary')).margin({ bottom: 24 })
          Text('图书、书签、阅读进度和阅读记录保存在当前设备。卸载应用会移除应用内数据，请保留原始图书文件。')
            .fontSize(16).lineHeight(26).fontColor($r('app.color.label_secondary')).margin({ bottom: 18 })
          Text('支持 TXT、无 DRM EPUB 和未加密 PDF；不按源文件大小设定导入上限，需有足够设备存储空间。')
            .fontSize(15).fontColor($r('app.color.label_secondary'))
          Text('新版 EPUB 保留书内图片、样式与目录链接；旧书可补全原文件。离线阅读不执行书内脚本，不加载外部资源；PDF 保留原页面版式。')
            .fontSize(13).lineHeight(21).fontColor($r('app.color.label_secondary')).margin({ top: 12 })
        }
      }.width('100%').padding(24).alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  tabPage(tab: string) {
      Scroll(this.nativeTabs ? tab === 'home' ? this.scroller : tab === 'library' ? this.libraryScroller : this.profileScroller : this.scroller) {
        Column() {
          if (!this.nativeTabs) { this.header(tab) }
          if (this.loading && this.books.length === 0) {
            EmptyState({ title: '正在打开书库', message: '', loading: true })
          } else if (this.loadError.length > 0 && !this.ready) {
            EmptyState({ title: '暂时无法打开书库', message: this.loadError, error: true,
              actionLabel: '重试', onImport: () => { this.bootstrap(); } })
          } else {
            Column() {
              if (tab === 'home') { this.homeContent() }
              else if (tab === 'library') { this.libraryContent() }
              else { this.profileContent() }
            }.width('100%').id('page_' + tab)
          }
          if (this.importing || this.coverBusy) {
            Row({ space: 12 }) {
              LoadingProgress().width(22).height(22).color($r('app.color.goal_accent'))
              Text(this.coverBusy ? '正在更新封面' : this.importMessage).fontSize(14).fontColor($r('app.color.label_secondary'))
            }.height(60)
          }
        }.width('100%').constraintSize({ maxWidth: ShelfLayout.MAX_WIDTH }).padding({ bottom: 120 })
      }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
  }

  @Builder
  homePage() { this.tabPage('home') }
  @Builder
  libraryPage() { this.tabPage('library') }
  @Builder
  profilePage() { this.tabPage('profile') }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.nativeTabs) {
        NativeShelfTabs({ selected: this.selectedTab, reduceMotion: this.readingSettings.reduceMotion,
          homeScroller: this.scroller, libraryScroller: this.libraryScroller, profileScroller: this.profileScroller,
          gridLayout: this.preferences.libraryLayout === 'grid', onSearch: () => this.search(),
          onLayout: () => { this.preferences.libraryLayout = this.preferences.libraryLayout === 'grid' ? 'list' : 'grid'; },
          onLibraryOptions: () => this.showSheet('library'),
          // BuilderParam invokes bare method references with the child as `this`.
          // Keep the page builders attached to Bookshelf (the owner of tabPage and its state).
          home: () => { this.homePage(); }, library: () => { this.libraryPage(); }, profile: () => { this.profilePage(); },
          onSelect: (tab: string) => { if (tab !== this.selectedTab) { this.selectTab(tab); } } })
      } else {
        ForEach([this.selectedTab], (tab: string) => {
          Column() { this.tabPage(tab) }.width('100%').height('100%')
            .transition(ReaderMotion.reveal(this.readingSettings.reduceMotion))
        }, (tab: string) => tab)
        GlassNavigation({ selected: this.selectedTab, windowWidth: this.windowWidth, reduceMotion: this.readingSettings.reduceMotion,
          onSelect: (tab: string) => this.selectTab(tab), onSearch: () => this.search() })
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.background'))
      .onAreaChange((oldArea: Area, area: Area) => { this.windowWidth = Number(area.width); })
      .bindSheet($$this.sheetVisible, this.sheetContent(), { height: this.sheetKind === 'reading' ? SheetSize.LARGE : this.sheetKind === 'book' ? 600 : 480,
        preferType: this.wide() ? SheetType.CENTER : SheetType.BOTTOM,
        width: this.wide() ? 540 : '100%', dragBar: !this.wide(), showClose: false,
        backgroundColor: this.sheetKind === 'reading' ? ThemeManager.resolve(this.readingSettings.theme, this.systemDark, this.preferences.appearance).chrome : $r('app.color.surface'),
        blurStyle: this.sheetKind === 'reading' ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THICK })
  }
}
