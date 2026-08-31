import { CapsuleButton } from './CapsuleButton';
import { Radius, TypeScale, Spacing } from '../theme/tokens';

/** 空态 —— docs/DESIGN.md §3.5 */
@ComponentV2
export struct EmptyState {
  @Event onImport: () => void = () => {};

  build() {
    Column({ space: Spacing.M }) {
      Text('读')
        .fontSize(40)
        .fontWeight(700)
        .fontColor($r('app.color.primary'))
        .width(96)
        .height(96)
        .textAlign(TextAlign.Center)
        .backgroundColor($r('app.color.brand_tint'))
        .borderRadius(Radius.L)
      Text('还没有图书')
        .fontSize(TypeScale.TITLE)
        .fontWeight(700)
        .fontColor($r('app.color.label_primary'))
        .margin({ top: Spacing.S })
      Text('从文件导入你的第一本 TXT，开始阅读')
        .fontSize(TypeScale.SUBHEAD)
        .fontColor($r('app.color.label_secondary'))
      CapsuleButton({ label: '导入图书', kind: 'primary', onTap: () => this.onImport() })
        .margin({ top: Spacing.S })
    }
    .width('100%')
    .padding({ top: 120, bottom: 48 })
    .alignItems(HorizontalAlign.Center)
  }
}
