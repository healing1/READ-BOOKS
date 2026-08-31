import { Book } from '../model/Models';
import { Radius, TypeScale, Spacing } from '../theme/tokens';

/** 书籍卡片 —— docs/DESIGN.md §3.5（kit/Card 派生：L=20 圆角、1px 边界、无阴影） */
@ComponentV2
export struct BookCard {
  @Param book: Book = new Book();
  @Event onOpen: () => void = () => {};
  @Event onDelete: () => void = () => {};

  build() {
    Column() {
      Column() {
        Text(this.book.title)
          .fontSize(TypeScale.TITLE)
          .fontWeight(700)
          .fontColor('#FFFFFF')
          .maxLines(3)
          .textAlign(TextAlign.Center)
          .lineHeight(30)
        Blank()
        Text(this.progressText())
          .fontSize(TypeScale.CAPTION)
          .fontColor('#FFFFFFCC')
      }
      .width('100%')
      .aspectRatio(0.72)
      .backgroundColor(this.book.coverColor)
      .borderRadius(Radius.L)
      .border({ width: 1, color: $r('app.color.separator') })
      .alignItems(HorizontalAlign.Center)
      .padding(Spacing.BASE)

      Column() {
        Text(this.book.title)
          .fontSize(TypeScale.SUBHEAD)
          .fontWeight(600)
          .fontColor($r('app.color.label_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.metaText())
          .fontSize(TypeScale.CAPTION)
          .fontColor($r('app.color.label_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: Spacing.S })
    }
    .width('100%')
    .onClick(() => this.onOpen())
    .onLongPress(() => this.onDelete())
  }

  private progressText(): string {
    if (this.book.charCount <= 0 || this.book.progressCharOffset <= 0) {
      return '未读';
    }
    const pct: number = Math.floor(this.book.progressCharOffset / this.book.charCount * 100);
    return pct + '%';
  }

  private metaText(): string {
    const kb: number = Math.max(1, Math.round(this.book.sizeBytes / 1024));
    return this.book.encoding.toUpperCase() + ' · ' + kb + ' KB';
  }
}
