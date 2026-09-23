import { TypeScale, Spacing } from '../theme/tokens';
import { IconButton } from './IconButton';
import { ReadingSettings } from '../model/ReadingSettings';
import { LightFeedback } from '../theme/ReaderMotion';
import { ReadingPalette } from '../theme/ThemeManager';

@ComponentV2
export struct HudTopBar {
  @Param palette: ReadingPalette | null = null;
  private settings: ReadingSettings = ReadingSettings.load();
  @Param title: string = '';
  @Param bookmarked: boolean = false;
  @Event onBack: () => void = () => {};
  @Event onBookmark: () => void = () => {};

  build() {
    Row({ space: Spacing.S }) {
      IconButton({ icon: $r('app.media.ic_back'), label: '返回书架', tint: this.palette?.text ?? $r('app.color.label_primary'), onAction: this.onBack }).id('reader_back')
      Text(this.title)
        .layoutWeight(1)
        .fontFamily('DM Sans')
        .fontSize(15)
        .fontWeight(600)
        .fontColor(this.palette?.text ?? $r('app.color.label_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
      IconButton({
        icon: this.bookmarked ? $r('app.media.ic_bookmark_filled') : $r('app.media.ic_bookmark'),
        label: this.bookmarked ? '移除本页书签' : '添加书签',
        selected: this.bookmarked,
        tint: this.palette?.text ?? $r('app.color.label_primary'),
        onAction: this.onBookmark
      })
    }
    .width('94%').constraintSize({ maxWidth: 760 })
    .height(52)
    .padding({ left: Spacing.S, right: Spacing.S })
    .id('reader_top_bar').backgroundColor(this.palette?.chrome ?? $r('app.color.glass_surface'))
    .backgroundBlurStyle(this.palette === null ? BlurStyle.COMPONENT_ULTRA_THICK : BlurStyle.NONE)
    .border({ width: 0.5, color: this.palette?.edge ?? $r('app.color.glass_edge'), radius: 26 })
    .shadow({ radius: 16, color: '#14000000', offsetY: 4 }).margin({ top: 12 })
  }
}

@ComponentV2
export struct HudBottomBar {
  @Param palette: ReadingPalette | null = null;
  private settings: ReadingSettings = ReadingSettings.load();
  @Param sliderValue: number = 0;
  @Param progressLabel: string = '';
  @Event onSlider: (value: number, done: boolean) => void = () => {};
  @Event onToc: () => void = () => {};
  @Event onSettings: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        IconButton({ icon: $r('app.media.ic_contents'), label: '目录与书签', tint: this.palette?.text ?? $r('app.color.label_primary'), onAction: this.onToc }).id('reader_toc')
        Text(this.progressLabel).layoutWeight(1).textAlign(TextAlign.Center)
          .fontSize(12).fontColor(this.palette?.meta ?? $r('app.color.label_secondary')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).accessibilityText('阅读进度，' + this.progressLabel)
        Button('Aa', { type: ButtonType.Circle }).width(44).height(44).fontSize(22).fontWeight(500)
          .fontColor(this.palette?.text ?? $r('app.color.label_primary')).backgroundColor(Color.Transparent)
          .id('reader_settings').accessibilityText('阅读设置')
          .attributeModifier(new LightFeedback(this.settings.reduceMotion)).onClick(() => this.onSettings())
      }.width('100%')
      Slider({ value: this.sliderValue, min: 0, max: 1000, step: 1 }).width('100%').height(28)
        .id('reader_progress').accessibilityText('全书阅读进度')
        .selectedColor(this.palette?.text ?? $r('app.color.label_primary'))
        .blockColor(this.palette?.text ?? $r('app.color.label_primary'))
        .onChange((value: number, mode: SliderChangeMode) => {
          this.onSlider(value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
        })
    }
    .width('94%').constraintSize({ maxWidth: 480 })
    .padding({ left: 16, right: 16, top: 4, bottom: 12 })
    .id('reader_bottom_bar').backgroundColor(this.palette?.chrome ?? $r('app.color.glass_surface'))
    .backgroundBlurStyle(this.palette === null ? BlurStyle.COMPONENT_ULTRA_THICK : BlurStyle.NONE)
    .border({ width: 0.5, color: this.palette?.edge ?? $r('app.color.glass_edge'), radius: 26 })
    .shadow({ radius: 16, color: '#14000000', offsetY: 4 }).margin({ bottom: 16 })
  }
}
