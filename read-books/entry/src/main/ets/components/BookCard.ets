import { iconTint } from '../theme/IconTint';
import { Book } from '../model/Models';
import { BookCover } from './BookCover';
import { ReadingSettings } from '../model/ReadingSettings';
import { LightFeedback } from '../theme/ReaderMotion';
import { CoverVisual } from '../reader/CoverVisual';

@ComponentV2
export struct BookCard {
  @Param book: Book = new Book();
  @Param finished: boolean = false;
  @Local coverRatio: number = 0.66;
  @Event onOpen: () => void = () => {};
  @Event onDelete: () => void = () => {};
  private settings: ReadingSettings = ReadingSettings.load();

  aboutToAppear(): void { this.updateCover(); }
  @Monitor('book')
  async updateCover(): Promise<void> {
    const path: string = this.book.coverPath;
    const visual = await CoverVisual.read(this.book);
    if (path === this.book.coverPath) { this.coverRatio = Math.max(0.25, Math.min(4, visual.ratio)); }
  }

  build() {
    Column() {
      Button({ type: ButtonType.Normal }) {
        BookCover({ book: this.book })
      }
      .width('100%').aspectRatio(this.coverRatio).constraintSize({ maxHeight: 420 }).padding(0).borderRadius(3).backgroundColor(Color.Transparent)
      .shadow({ radius: 12, color: '#24000000', offsetY: 5 })
      .attributeModifier(new LightFeedback(this.settings.reduceMotion))
      .id('book_open_' + this.book.id).accessibilityText('阅读《' + this.book.title + '》')
      .onClick(() => this.onOpen())
      Text(this.book.title.replace('示例 · ', ''))
        .fontSize(15).fontWeight(500).fontColor($r('app.color.label_primary')).width('100%')
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 10 })
      Text(this.book.author || this.book.format.toUpperCase())
        .fontSize(12).fontColor($r('app.color.label_secondary')).width('100%')
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 4 })
      Row() {
        Text(this.finished ? '已读完' : Math.floor(this.book.progressCharOffset / Math.max(1, this.book.charCount) * 100) + '%')
          .fontSize(14).fontColor($r('app.color.label_secondary')).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.shelf_more')).width(22).height(22).fillColor($r('app.color.label_secondary'))
        }
        .width(44).height(44).backgroundColor(Color.Transparent).id('book_manage_' + this.book.id)
        .attributeModifier(new LightFeedback(this.settings.reduceMotion))
        .accessibilityText('管理《' + this.book.title + '》').onClick(() => this.onDelete())
      }.width('100%').height(44)
    }
    .width('100%').gesture(LongPressGesture().onAction(() => this.onDelete()))
  }
}
