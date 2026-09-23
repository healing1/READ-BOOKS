import { Book } from '../model/Models';

/** A decoded local cover, with a readable typeset fallback for missing or invalid images. */
@ComponentV2
export struct BookCover {
  @Param book: Book = new Book();
  @Param compact: boolean = false;
  @Local imageFailed: boolean = false;

  @Monitor('book')
  coverChanged(): void { this.imageFailed = false; }

  private tone(): string {
    const tones: string[] = ['#235C83', '#446C59', '#913B45', '#7A664C', '#565273', '#427276'];
    return tones[Math.max(0, this.book.id - 1) % tones.length];
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.book.coverPath.length > 0 && !this.imageFailed) {
        Image('file://' + this.book.coverPath).width('100%').height('100%').objectFit(ImageFit.Contain)
          .id('cover_image_' + this.book.id)
          .onError(() => { this.imageFailed = true; })
      } else {
      Stack({ alignContent: Alignment.Start }) {
      Column() {
        Text(this.book.title.replace('示例 · ', '').replace('（节选）', ''))
          .fontSize(this.compact ? 13 : 24).fontWeight(600).fontColor('#FFFFFF')
          .textAlign(TextAlign.Center).maxLines(this.compact ? 3 : 6)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').layoutWeight(1)
        if (!this.compact) {
          Text(this.book.author || (this.book.title.indexOf('西游记') >= 0 ? '吴承恩' : 'READ BOOKS'))
            .fontSize(12).fontColor('#CDFFFFFF').textAlign(TextAlign.Center)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
      }
      .width('100%').height('100%').padding(this.compact ? 8 : 20)
      .border({ width: 0.5, color: '#50FFFFFF' }).margin({ left: this.compact ? 3 : 8 })
      Row().width(this.compact ? 3 : 7).height('100%').backgroundColor('#40000000')
      Row().width(1).height('100%').backgroundColor('#60FFFFFF').margin({ left: this.compact ? 4 : 9 })
      }.width('100%').height('100%')
        .padding({ top: this.compact ? 3 : 8, bottom: this.compact ? 3 : 8, right: this.compact ? 3 : 8 })
        .id('cover_text_' + this.book.id)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.book.coverPath.length > 0 && !this.imageFailed ? Color.Transparent : this.tone())
    .borderRadius(3).clip(true).accessibilityLevel('no-hide-descendants')
  }
}
