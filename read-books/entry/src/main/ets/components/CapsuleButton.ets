import { Radius, TypeScale } from '../theme/tokens';

/** 胶囊按钮 —— docs/DESIGN.md §3.5（kit/Button：primary 填充 / secondary 文字 / text） */
@ComponentV2
export struct CapsuleButton {
  @Param label: string = '';
  @Param kind: string = 'primary';
  @Param heightVp: number = 48;
  @Event onTap: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(TypeScale.HEADLINE)
      .fontWeight(this.kind === 'primary' ? 600 : 400)
      .fontColor(this.kind === 'primary'
        ? $r('app.color.on_primary')
        : (this.kind === 'secondary' ? $r('app.color.primary') : $r('app.color.label_secondary')))
      .height(this.heightVp)
      .padding({ left: 24, right: 24 })
      .backgroundColor(this.kind === 'primary' ? $r('app.color.primary') : Color.Transparent)
      .borderRadius(this.heightVp / 2)
      .onClick(() => this.onTap())
  }
}
