import { TouchTarget } from '../theme/tokens';
import { ReadingSettings } from '../model/ReadingSettings';
import { LightFeedback } from '../theme/ReaderMotion';

/** App-owned 44vp icon hit area; system sheets and dialogs keep their native appearance. */
@ComponentV2
export struct IconButton {
  @Param icon: Resource = $r('app.media.ic_close');
  @Param label: string = '';
  @Param selected: boolean = false;
  @Param destructive: boolean = false;
  @Param disabled: boolean = false;
  @Param tint: ResourceColor = $r('app.color.label_primary');
  @Event onAction: () => void = () => {};
  private settings: ReadingSettings = ReadingSettings.load();

  private symbol(): Resource {
    if (this.icon.id === $r('app.media.ic_back').id) { return $r('sys.symbol.chevron_left'); }
    if (this.icon.id === $r('app.media.ic_contents').id) { return $r('sys.symbol.list_bullet'); }
    if (this.icon.id === $r('app.media.ic_bookmark').id) { return $r('sys.symbol.bookmark'); }
    if (this.icon.id === $r('app.media.ic_bookmark_filled').id) { return $r('sys.symbol.bookmark_fill'); }
    if (this.icon.id === $r('app.media.ic_delete').id) { return $r('sys.symbol.trash'); }
    if (this.icon.id === $r('app.media.nav_grid').id) { return $r('sys.symbol.square_grid_2x2'); }
    return $r('sys.symbol.xmark');
  }

  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(this.symbol()).fontSize(21).fontWeight(FontWeight.Regular)
        .fontColor([this.destructive ? $r('app.color.destructive') : this.tint])
        .accessibilityLevel('no')
    }
    .width(TouchTarget.MIN)
    .height(TouchTarget.MIN)
    .padding(0).backgroundColor(Color.Transparent)
    .borderRadius(22)
    .opacity(this.disabled ? 0.35 : 1)
    .enabled(!this.disabled)
    .focusable(true)
    .accessibilityGroup(true)
    .accessibilityText(this.label)
    .attributeModifier(new LightFeedback(this.settings.reduceMotion))
    .onClick(() => this.onAction())
  }
}
