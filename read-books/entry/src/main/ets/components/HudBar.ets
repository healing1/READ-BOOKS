import { TouchTarget, TypeScale, Spacing } from '../theme/tokens';

/** 阅读器 HUD 顶栏 —— docs/DESIGN.md §4.3（毛玻璃材质条） */
@ComponentV2
export struct HudTopBar {
  @Param title: string = '';
  @Event onBack: () => void = () => {};

  build() {
    Row() {
      Text('‹')
        .fontSize(30)
        .fontWeight(500)
        .fontColor($r('app.color.label_primary'))
        .width(TouchTarget.MIN)
        .height(TouchTarget.MIN)
        .textAlign(TextAlign.Center)
        .onClick(() => this.onBack())
      Text(this.title)
        .layoutWeight(1)
        .fontSize(TypeScale.HEADLINE)
        .fontWeight(600)
        .fontColor($r('app.color.label_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
      Blank()
        .width(TouchTarget.MIN)
    }
    .width('100%')
    .height(52)
    .padding({ left: Spacing.S, right: Spacing.S })
    .backgroundColor($r('app.color.hud_bar'))
    .backgroundBlurStyle(BlurStyle.MaterialThin)
  }
}

/** 阅读器 HUD 底栏：目录 · 全书进度滑杆 · Aa 设置 —— docs/DESIGN.md §4.3 */
@ComponentV2
export struct HudBottomBar {
  @Param sliderValue: number = 0;
  @Param progressLabel: string = '';
  @Event onSlider: (value: number, done: boolean) => void = () => {};
  @Event onToc: () => void = () => {};
  @Event onSettings: () => void = () => {};

  build() {
    Column() {
      Text(this.progressLabel)
        .fontSize(TypeScale.CAPTION)
        .fontColor($r('app.color.label_secondary'))
        .margin({ bottom: Spacing.XS })
      Row({ space: Spacing.M }) {
        Text('目录')
          .fontSize(TypeScale.SUBHEAD)
          .fontWeight(500)
          .fontColor($r('app.color.label_primary'))
          .height(TouchTarget.MIN)
          .padding({ left: Spacing.S, right: Spacing.S })
          .textAlign(TextAlign.Center)
          .onClick(() => this.onToc())
        Slider({ value: this.sliderValue, min: 0, max: 1000, style: SliderStyle.OutSet })
          .layoutWeight(1)
          .selectedColor($r('app.color.primary'))
          .blockColor($r('app.color.primary'))
          .trackColor($r('app.color.separator'))
          .onChange((value: number, mode: SliderChangeMode) => {
            const done: boolean = mode === SliderChangeMode.End || mode === SliderChangeMode.Click;
            this.onSlider(value, done);
          })
        Text('Aa')
          .fontSize(TypeScale.HEADLINE)
          .fontWeight(600)
          .fontColor($r('app.color.label_primary'))
          .height(TouchTarget.MIN)
          .padding({ left: Spacing.S, right: Spacing.S })
          .textAlign(TextAlign.Center)
          .onClick(() => this.onSettings())
      }
      .width('100%')
    }
    .width('100%')
    .height(84)
    .padding({ left: Spacing.BASE, right: Spacing.BASE, top: Spacing.S })
    .backgroundColor($r('app.color.hud_bar'))
    .backgroundBlurStyle(BlurStyle.MaterialThin)
    .alignItems(HorizontalAlign.Center)
  }
}
