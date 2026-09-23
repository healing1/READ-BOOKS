import { iconTint } from '../theme/IconTint';
import { CapsuleButton } from './CapsuleButton';
import { Radius, TypeScale, Spacing } from '../theme/tokens';

/** 空态 —— docs/DESIGN.md §3.5 */
@ComponentV2
export struct EmptyState {
  @Event onImport: () => void = () => {};
  @Param title: string = '还没有图书';
  @Param message: string = '导入 TXT、EPUB 或 PDF，开始阅读';
  @Param actionLabel: string = '导入图书';
  @Param loading: boolean = false;
  @Param error: boolean = false;
  @Param actionEnabled: boolean = true;
  @Param actionId: string = 'shelf_empty_import';

  build() {
    Column({ space: Spacing.M }) {
      Stack() {
        if (this.loading) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color($r('app.color.primary'))
        } else {
          Image(this.error ? $r('app.media.shelf_alert') : $r('app.media.shelf_book'))
            .width(40)
            .height(40)
            .colorFilter(iconTint(this.getUIContext(), $r('app.color.primary')))
            .accessibilityLevel('no')
        }
      }
        .width(96)
        .height(96)
        .backgroundColor($r('app.color.brand_tint'))
        .borderRadius(Radius.L)
      Text(this.title)
        .fontSize(TypeScale.TITLE)
        .fontFamily('DM Sans')
        .fontWeight(700)
        .fontColor($r('app.color.label_primary'))
        .textAlign(TextAlign.Center)
        .margin({ top: Spacing.S })
      Text(this.message)
        .fontSize(TypeScale.SUBHEAD)
        .fontColor($r('app.color.label_secondary'))
        .textAlign(TextAlign.Center)
        .lineHeight(22)
        .constraintSize({ maxWidth: 340 })
      if (!this.loading) {
        CapsuleButton({ label: this.actionLabel, kind: 'primary', isEnabled: this.actionEnabled,
          controlId: this.actionId,
          onTap: () => this.onImport() })
          .margin({ top: Spacing.S })
      }
    }
    .width('100%')
    .padding({ left: Spacing.L, right: Spacing.L, top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }
}
