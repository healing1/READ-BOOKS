import { HdsTabs, HdsTabsController, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType,
  HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { NativeMaterial } from '../theme/NativeMaterial';
import { SymbolGlyphModifier } from '@kit.ArkUI';

// Keep the API23/24 HDS host on ViewPU: a ViewV2 host can build its children
// without attaching them to the window on HarmonyOS 6.1.1 (blank root JsView).
@Component
export struct NativeShelfTabs {
  @Prop @Watch('selectedChanged') selected: string = 'home';
  @Prop reduceMotion: boolean = false;
  @Prop gridLayout: boolean = true;
  homeScroller: Scroller = new Scroller();
  libraryScroller: Scroller = new Scroller();
  profileScroller: Scroller = new Scroller();
  onSelect: (tab: string) => void = () => {};
  onSearch: () => void = () => {};
  onLayout: () => void = () => {};
  onLibraryOptions: () => void = () => {};
  @BuilderParam home: () => void;
  @BuilderParam library: () => void;
  @BuilderParam profile: () => void;
  private controller: HdsTabsController = new HdsTabsController();

  private tabSymbol(icon: Resource, filled: Resource): TabBarSymbol {
    return { normal: new SymbolGlyphModifier(icon).fontSize(23).fontWeight(FontWeight.Regular)
      .fontColor([$r('app.color.label_secondary')]).renderingStrategy(SymbolRenderingStrategy.SINGLE),
      selected: new SymbolGlyphModifier(filled).fontSize(23).fontWeight(FontWeight.Medium)
        .fontColor([$r('app.color.label_primary')]).renderingStrategy(SymbolRenderingStrategy.SINGLE) };
  }

  selectedChanged(): void { this.controller.changeIndex(this.selected === 'home' ? 0 : this.selected === 'library' ? 1 : 2); }

  private menus(): HdsNavigationMenuContentOptions {
    return { value: this.selected === 'library' ? [
      { content: { label: '搜索书库', icon: $r('sys.symbol.magnifyingglass'), componentId: 'library_search_button', action: () => this.onSearch() } },
      { content: { label: '切换书库布局', icon: this.gridLayout ? $r('sys.symbol.list_bullet') : $r('sys.symbol.square_grid_2x2'),
        componentId: 'library_layout', action: () => this.onLayout() } },
      { content: { label: '书库选项', icon: $r('sys.symbol.more'), componentId: 'library_more', action: () => this.onLibraryOptions() } }
    ] : [] };
  }

  build() {
    HdsNavigation() {
    HdsTabs({ barPosition: BarPosition.End, controller: this.controller,
      index: this.selected === 'home' ? 0 : this.selected === 'library' ? 1 : 2 }) {
      TabContent() { this.home() }
        .tabBar(BottomTabBarStyle.of(this.tabSymbol($r('sys.symbol.house'), $r('sys.symbol.house_fill')), '主页')
          .labelStyle({ selectedColor: $r('app.color.label_primary'), unselectedColor: $r('app.color.label_secondary'), font: { size: 12 } }))
        .id('native_tab_home')
      TabContent() { this.library() }
        .tabBar(BottomTabBarStyle.of(this.tabSymbol($r('sys.symbol.book'), $r('sys.symbol.book_open_fill')), '书库')
          .labelStyle({ selectedColor: $r('app.color.label_primary'), unselectedColor: $r('app.color.label_secondary'), font: { size: 12 } }))
        .id('native_tab_library')
      TabContent() { this.profile() }
        .tabBar(BottomTabBarStyle.of(this.tabSymbol($r('sys.symbol.person'), $r('sys.symbol.person_fill')), '我的')
          .labelStyle({ selectedColor: $r('app.color.label_primary'), unselectedColor: $r('app.color.label_secondary'), font: { size: 12 } }))
        .id('native_tab_profile')
    }
    .width('100%').height('100%').barOverlap(true).scrollable(false)
    .animationDuration(this.reduceMotion ? 0 : 260)
    .barFloatingStyle({
      barWidth: { smallWidth: '88%', mediumWidth: 400, largeWidth: 480 },
      barBottomMargin: 16,
      systemMaterialEffect: NativeMaterial.options(this.reduceMotion),
      thermoCtrl: true
    })
    .onChange((index: number) => this.onSelect(['home', 'library', 'profile'][index]))
    .id('native_shelf_tabs')
    }
    .mode(NavigationMode.Stack).hideBackButton(true).titleMode(HdsNavigationTitleMode.FULL)
    .titleBar({
      enableComponentSafeArea: true,
      content: { title: { mainTitle: this.selected === 'home' ? '主页' : this.selected === 'library' ? '书库' : '我的' }, menu: this.menus() },
      style: { systemMaterialEffect: NativeMaterial.options(this.reduceMotion), thermoCtrl: true,
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR } }
    })
    .bindToScrollable([this.selected === 'home' ? this.homeScroller :
      this.selected === 'library' ? this.libraryScroller : this.profileScroller])
    .width('100%').height('100%').backgroundColor($r('app.color.background')).id('native_shelf_navigation')
  }
}
