import { ReaderMotion, LightFeedback } from '../theme/ReaderMotion';
@ComponentV2
export struct GlassNavigation {
  @Param selected: string = 'home';
  @Param windowWidth: number = 390;
  @Param reduceMotion: boolean = false;
  @Event onSelect: (tab: string) => void = () => {};
  @Event onSearch: () => void = () => {};

  private wide(): boolean { return this.windowWidth >= 840; }
  private barWidth(): number { return Math.max(210, Math.min(this.wide() ? 456 : 340, this.windowWidth - 114)); }
  private itemWidth(): number { return (this.barWidth() - 8) / 3; }
  private index(): number { return this.selected === 'home' ? 0 : this.selected === 'library' ? 1 : 2; }

  @Builder
  label(title: string, icon: Resource) {
    SymbolGlyph(icon).fontSize(23).fontWeight(FontWeight.Regular)
      .fontColor([$r('app.color.label_primary')])
    Text(title).fontSize(this.wide() ? 15 : 11).fontWeight(600).fontColor($r('app.color.label_primary'))
  }

  @Builder
  item(key: string, title: string, icon: Resource) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      if (this.wide()) {
        Row({ space: 9 }) { this.label(title, icon) }.justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 2 }) { this.label(title, icon) }.justifyContent(FlexAlign.Center)
      }
    }
    .width(this.itemWidth()).height(54).padding(0).borderRadius(28).backgroundColor(Color.Transparent)
    .hoverEffect(HoverEffect.None)
    .attributeModifier(new LightFeedback(this.reduceMotion))
    .id('tab_' + key).accessibilityText(title + (this.selected === key ? '，已选择' : ''))
    .onClick(() => this.onSelect(key))
  }

  build() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Start }) {
        Row().width(this.itemWidth()).height(54).borderRadius(28)
          .backgroundColor($r('app.color.glass_selected'))
          .border({ width: 0.5, color: $r('app.color.glass_highlight') })
          .shadow({ radius: 5, color: '#14000000', offsetY: 2 })
          .translate({ x: this.itemWidth() * this.index() })
          .animation(ReaderMotion.spring(this.reduceMotion))
          .id('nav_selection').hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        Row() {
          this.item('home', '主页', $r('sys.symbol.house'))
          this.item('library', '书库', $r('sys.symbol.book'))
          this.item('profile', '我的', $r('sys.symbol.person'))
        }
      }
      .padding(4).width(this.barWidth()).height(64).borderRadius(34)
      .backgroundColor($r('app.color.glass_surface')).backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .border({ width: 0.75, color: $r('app.color.glass_edge') })
      .shadow({ radius: 24, color: '#24000000', offsetY: 8 })
      .attributeModifier(new LightFeedback(this.reduceMotion, true)).id('navigation_bar')
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(23).fontColor([$r('app.color.label_primary')])
      }
      .width(64).height(64).padding(0)
      .backgroundColor($r('app.color.glass_surface')).backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .border({ width: 0.75, color: $r('app.color.glass_edge') })
      .shadow({ radius: 24, color: '#24000000', offsetY: 8 })
      .attributeModifier(new LightFeedback(this.reduceMotion))
      .id('nav_search').accessibilityText('搜索书库').onClick(() => this.onSearch())
    }
    .padding({ bottom: this.wide() ? 20 : 12, top: 16 })
  }
}
