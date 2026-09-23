import { Book } from '../model/Models';
import { BookCover } from './BookCover';
import { CoverVisual } from '../reader/CoverVisual';
import { LightFeedback } from '../theme/ReaderMotion';

/** The home shelf uses the actual cover ratio, just like the library. */
@ComponentV2
export struct SuggestedBook {
  @Param book: Book = new Book();
  @Param finished: boolean = false;
  @Param wide: boolean = false;
  @Param reduced: boolean = false;
  @Local ratio: number = 0.66;
  @Event onOpen: () => void = () => {};

  aboutToAppear(): void { this.updateCover(); }
  @Monitor('book')
  async updateCover(): Promise<void> {
    const path: string = this.book.coverPath;
    const visual = await CoverVisual.read(this.book);
    if (path === this.book.coverPath) { this.ratio = Math.max(0.25, Math.min(4, visual.ratio)); }
  }
  build() {
    Column({ space: 10 }) {
      Button({ type: ButtonType.Normal }) { BookCover({ book: this.book }) }
        .width('100%').aspectRatio(this.ratio).constraintSize({ maxHeight: 300 })
        .borderRadius(3).padding(0).backgroundColor(Color.Transparent)
        .shadow({ radius: 10, color: '#24000000', offsetY: 5 })
        .attributeModifier(new LightFeedback(this.reduced))
        .id('home_book_' + this.book.id).accessibilityText('阅读《' + this.book.title + '》').onClick(() => this.onOpen())
      Text(this.book.title.replace('示例 · ', '')).fontSize(14).fontWeight(500).fontColor($r('app.color.label_primary'))
        .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.finished ? '已读完' : this.book.format.toUpperCase() + ' · ' +
        Math.floor(this.book.progressCharOffset / Math.max(1, this.book.charCount) * 100) + '%')
        .fontSize(12).fontColor($r('app.color.label_secondary')).width('100%')
    }.width(this.wide ? 146 : 126).alignItems(HorizontalAlign.Start)
  }
}
