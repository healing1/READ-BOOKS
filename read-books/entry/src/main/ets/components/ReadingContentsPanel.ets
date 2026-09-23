import { Book, Chapter, Bookmark } from '../model/Models';
import { IconButton } from './IconButton';
import { ReadingChoice } from './ReadingSettingsPanel';

class ContentsSource implements IDataSource {
  private items: Chapter[] = [];
  private listeners: DataChangeListener[] = [];
  update(items: Chapter[]): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
  totalCount(): number { return this.items.length; }
  getData(index: number): Chapter { return this.items[index]; }
  indexOf(chapterIndex: number): number { return this.items.findIndex((chapter: Chapter) => chapter.idx === chapterIndex); }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener);
  }
}

@ComponentV2
struct ChapterRow {
  @Param chapter: Chapter = new Chapter();
  @Param current: number = -1;
  @Param pending: boolean = false;
  @Event onOpen: (offset: number) => void = () => {};
  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 16 }) {
        Text((this.chapter.idx + 1).toString().padStart(2, '0')).width(30)
          .fontSize(12).fontColor($r('app.color.label_tertiary'))
        Text(this.chapter.title).layoutWeight(1).fontSize(16).lineHeight(24)
          .fontWeight(this.chapter.idx === this.current ? 600 : 400)
          .fontColor($r('app.color.label_primary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.chapter.idx === this.current) {
          SymbolGlyph($r('sys.symbol.book')).fontSize(18).fontColor([$r('app.color.primary')])
        }
      }.width('100%').constraintSize({ minHeight: 36 }).padding({ top: 12, bottom: 12 })
    }
    .id('chapter_' + this.chapter.idx).width('100%').padding({ left: 16, right: 16 }).borderRadius(14)
    .backgroundColor(this.chapter.idx === this.current ? $r('app.color.brand_tint') : Color.Transparent)
    .enabled(!this.pending).accessibilityText(this.chapter.title + (this.chapter.idx === this.current ? '，当前章节' : ''))
    .onClick(() => this.onOpen(this.chapter.startOffset))
  }
}

@ComponentV2
export struct ReadingContentsPanel {
  @Param book: Book = new Book();
  @Param chapters: Chapter[] = [];
  @Param bookmarks: Bookmark[] = [];
  @Param current: number = -1;
  @Param pending: boolean = false;
  @Event onOpen: (offset: number) => void = () => {};
  @Event onAddBookmark: () => void = () => {};
  @Event onDeleteBookmark: (bookmark: Bookmark) => void = () => {};
  @Event onClose: () => void = () => {};
  @Local tab: string = 'chapters';
  @Local query: string = '';
  @Local resultCount: number = 0;
  private source: ContentsSource = new ContentsSource();
  private scroller: Scroller = new Scroller();
  private scrollTimer: number = -1;
  private active: boolean = false;

  aboutToAppear(): void { this.active = true; this.filter(); }
  aboutToDisappear(): void { this.active = false; clearTimeout(this.scrollTimer); }
  @Monitor('chapters', 'query')
  filter(): void {
    const query: string = this.query.trim().toLocaleLowerCase();
    const items: Chapter[] = query.length === 0 ? this.chapters :
      this.chapters.filter((chapter: Chapter) => chapter.title.toLocaleLowerCase().includes(query));
    this.resultCount = items.length;
    this.source.update(items);
  }
  private locateCurrent(): void {
    this.query = '';
    this.filter();
    clearTimeout(this.scrollTimer);
    this.scrollTimer = setTimeout(() => {
      if (this.active && this.tab === 'chapters' && this.query.length === 0) {
        const index: number = this.source.indexOf(this.current);
        if (index >= 0) { this.scroller.scrollToIndex(index, false, ScrollAlign.CENTER); }
      }
    }, 80);
  }
  private bookmarkChapter(offset: number): string {
    let low: number = 0;
    let high: number = this.chapters.length - 1;
    while (low < high) {
      const mid: number = Math.floor((low + high) / 2);
      if (offset < this.chapters[mid].endOffset) { high = mid; } else { low = mid + 1; }
    }
    return this.chapters[low]?.title ?? '书签';
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 5 }) {
          Text('目录与书签').fontSize(24).fontWeight(700).fontColor($r('app.color.label_primary'))
          Text(this.book.title.replace('示例 · ', '')).fontSize(13).fontColor($r('app.color.label_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        IconButton({ label: '关闭目录', onAction: () => this.onClose() }).id('contents_close')
      }.padding({ left: 24, right: 16, top: 12 })
      Row({ space: 4 }) {
        ReadingChoice({ label: '章节 · ' + this.chapters.length, keyName: 'contents_chapters', selected: this.tab === 'chapters',
          onChoose: () => { this.tab = 'chapters'; } }).layoutWeight(1)
        ReadingChoice({ label: '书签 · ' + this.bookmarks.length, keyName: 'contents_bookmarks', selected: this.tab === 'bookmarks',
          onChoose: () => { this.tab = 'bookmarks'; } }).layoutWeight(1)
      }.padding(4).backgroundColor($r('app.color.separator')).borderRadius(16).margin({ left: 24, right: 24 })
      if (this.pending) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18)
          Text('正在打开…').fontSize(13).fontColor($r('app.color.label_secondary'))
        }.height(24)
      }
      if (this.tab === 'chapters') {
        if (this.chapters.length > 8) {
          Search({ value: this.query, placeholder: '搜索章节' }).id('contents_search')
            .height(44).margin({ left: 24, right: 24 }).onChange((value: string) => { this.query = value; })
        }
        Row() {
          Text(this.query.length > 0 ? this.resultCount + ' 个结果' : '轻点章节开始阅读')
            .fontSize(12).fontColor($r('app.color.label_secondary')).layoutWeight(1)
          Button('当前章节', { type: ButtonType.Capsule }).fontSize(13).height(36)
            .fontColor($r('app.color.primary')).backgroundColor(Color.Transparent)
            .id('contents_current').onClick(() => this.locateCurrent())
        }.padding({ left: 28, right: 20 }).width('100%')
        if (this.resultCount === 0) {
          Text('没有找到匹配的章节').fontSize(15).fontColor($r('app.color.label_secondary')).layoutWeight(1)
        } else {
          List({ scroller: this.scroller, space: 4 }) {
            LazyForEach(this.source, (chapter: Chapter) => {
              ListItem() {
                ChapterRow({ chapter: chapter, current: this.current, pending: this.pending, onOpen: this.onOpen })
              }
            }, (chapter: Chapter) => chapter.idx.toString())
          }.id('contents_list').layoutWeight(1).padding({ left: 12, right: 12 }).scrollBar(BarState.Auto)
            .onAppear(() => { if (this.query.length === 0) { this.locateCurrent(); } })
        }
      } else if (this.bookmarks.length === 0) {
        Column({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.bookmark')).fontSize(36).fontColor([$r('app.color.label_tertiary')])
          Text('留住想再读的地方').fontSize(19).fontWeight(600).fontColor($r('app.color.label_primary'))
          Text('书签会记住这一页，方便下次回来。').fontSize(14).fontColor($r('app.color.label_secondary'))
          Button('添加当前页书签').fontSize(15).height(44).enabled(!this.pending)
            .id('contents_add_bookmark').onClick(() => this.onAddBookmark())
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(24)
      } else {
        List({ space: 12 }) {
          ForEach(this.bookmarks, (bookmark: Bookmark) => {
            ListItem() {
              Row({ space: 8 }) {
                Button({ type: ButtonType.Normal }) {
                  Column({ space: 10 }) {
                    Text(this.bookmarkChapter(bookmark.charOffset)).fontSize(12).fontWeight(600)
                      .fontColor($r('app.color.primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(bookmark.excerpt).fontSize(16).lineHeight(24).fontColor($r('app.color.label_primary'))
                      .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(Math.round(bookmark.charOffset / Math.max(1, this.book.charCount - 1) * 100) + '% · ' +
                      new Date(bookmark.createdAt).toLocaleDateString()).fontSize(12).fontColor($r('app.color.label_secondary'))
                  }.width('100%').alignItems(HorizontalAlign.Start).padding(16)
                }.layoutWeight(1).padding(0).backgroundColor(Color.Transparent).enabled(!this.pending)
                  .onClick(() => this.onOpen(bookmark.charOffset))
                IconButton({ icon: $r('app.media.ic_delete'), label: '删除书签', destructive: true,
                  onAction: () => this.onDeleteBookmark(bookmark) }).margin({ right: 8 })
              }.width('100%').backgroundColor($r('app.color.surface')).borderRadius(18)
            }
          }, (bookmark: Bookmark) => bookmark.id.toString())
        }.layoutWeight(1).padding({ left: 24, right: 24 }).scrollBar(BarState.Auto)
      }
    }.width('100%').height('100%').padding({ bottom: 24 }).backgroundColor($r('app.color.background'))
  }
}
