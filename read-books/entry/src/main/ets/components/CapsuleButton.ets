import { TypeScale, TouchTarget } from '../theme/tokens';
import { ReadingSettings } from '../model/ReadingSettings';
import { LightFeedback } from '../theme/ReaderMotion';

/** 胶囊按钮 —— docs/DESIGN.md §3.5（kit/Button：primary 填充 / secondary 文字 / text） */
@ComponentV2
export struct CapsuleButton {
  @Param label: string = '';
  @Param kind: string = 'primary';
  @Param heightVp: number = 48;
  @Param isEnabled: boolean = true;
  @Param controlId: string = 'capsule_action';
  @Event onTap: () => void = () => {};
  private settings: ReadingSettings = ReadingSettings.load();

  build() {
    Button(this.label, { type: ButtonType.Capsule })
      .fontSize(TypeScale.HEADLINE)
      .fontFamily('DM Sans')
      .fontWeight(this.kind === 'primary' ? 600 : 400)
      .fontColor(this.kind === 'primary'
        ? $r('app.color.on_primary')
        : (this.kind === 'secondary' ? $r('app.color.primary') : $r('app.color.label_secondary')))
      .height(Math.max(TouchTarget.MIN, this.heightVp))
      .padding({ left: 24, right: 24 })
      .backgroundColor(this.kind === 'primary' ? $r('app.color.primary') : Color.Transparent)
      .borderRadius(Math.max(TouchTarget.MIN, this.heightVp) / 2)
      .enabled(this.isEnabled)
      .id(this.controlId)
      .accessibilityText(this.label)
      .attributeModifier(new LightFeedback(this.settings.reduceMotion))
      .onClick(() => this.onTap())
  }
}
