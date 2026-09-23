import { ReadingPalette, ThemeManager } from '../theme/ThemeManager';
import { ReadingSettings } from '../model/ReadingSettings';
import { IconButton } from './IconButton';
import { ReadingAssets } from '../reader/ReadingAssets';
import { ReadingFonts } from '../reader/ReadingFonts';

@ComponentV2
struct FontChoice {
  @Param palette: ReadingPalette = ThemeManager.WHITE;
  @Param keyName: string = '';
  @Param label: string = '';
  @Param family: string = 'sans-serif';
  @Param selected: boolean = false;
  @Param disabled: boolean = false;
  @Event onChoose: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Text('阅读').fontFamily(this.family).fontSize(26).fontColor(this.palette.text)
          .height(40).width('100%').textAlign(TextAlign.Center)
        Text(this.label).fontSize(13).fontColor(this.palette.meta)
      }.width('100%').padding({ top: 14, bottom: 14 })
    }.id('font_' + this.keyName).width('100%').backgroundColor(this.palette.bg).borderRadius(16)
    .border({ width: this.selected ? 2 : 0.5, color: this.selected ? $r('app.color.primary') : this.palette.edge, radius: 16 }).clip(true)
    .accessibilityText(this.label + (this.selected ? '，已选择' : '')).enabled(!this.disabled)
    .onClick(() => this.onChoose())
  }
}

/** Reactive component parameters keep selection in sync while the sheet stays open. */
@ComponentV2
export struct ReadingChoice {
  @Param palette: ReadingPalette = ThemeManager.WHITE;
  @Param label: string = '';
  @Param keyName: string = '';
  @Param selected: boolean = false;
  @Param disabled: boolean = false;
  @Event onChoose: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Text(this.label).fontSize(15).fontWeight(this.selected ? 600 : 400)
        .fontColor(this.palette.text)
    }
    .id(this.keyName).width('100%').height(44).borderRadius(12)
    .backgroundColor(this.selected ? this.palette.bg : Color.Transparent)
    .border({ width: this.selected ? 0.5 : 0, color: this.palette.edge, radius: 12 }).clip(true)
    .opacity(this.disabled ? 0.35 : 1).enabled(!this.disabled)
    .accessibilityText(this.label + (this.selected ? '，已选择' : '') + (this.disabled ? '，宽屏时可用' : ''))
    .onClick(() => this.onChoose())
  }
}

@ComponentV2
struct TypeStepper {
  @Param palette: ReadingPalette = ThemeManager.WHITE;
  @Param label: string = '';
  @Param keyName: string = '';
  @Param value: number = 0;
  @Param minimum: number = 0;
  @Param maximum: number = 0;
  @Param decimals: number = 0;
  @Event onStep: (delta: number) => void = () => {};

  build() {
    Row({ space: 8 }) {
      Text(this.label).fontSize(16).fontColor(this.palette.text).layoutWeight(1)
      Button('−', { type: ButtonType.Circle }).width(40).height(40).fontSize(23)
        .fontColor(this.palette.text).backgroundColor(this.palette.chrome)
        .enabled(this.value > this.minimum).opacity(this.value > this.minimum ? 1 : 0.3)
        .id(this.keyName + '_minus').accessibilityText('减小' + this.label).onClick(() => this.onStep(-1))
      Text(this.value.toFixed(this.decimals)).width(44).textAlign(TextAlign.Center)
        .fontSize(16).fontColor(this.palette.text).id(this.keyName + '_value')
      Button('+', { type: ButtonType.Circle }).width(40).height(40).fontSize(23)
        .fontColor(this.palette.text).backgroundColor(this.palette.chrome)
        .enabled(this.value < this.maximum).opacity(this.value < this.maximum ? 1 : 0.3)
        .id(this.keyName + '_plus').accessibilityText('增大' + this.label).onClick(() => this.onStep(1))
    }
    .width('100%').padding(16)
  }
}

@ComponentV2
struct ThemeChoice {
  @Param palette: ReadingPalette = ThemeManager.WHITE;
  @Param keyName: string = '';
  @Param label: string = '';
  @Param selected: boolean = false;
  @Param paperColor: ResourceColor = Color.White;
  @Param inkColor: ResourceColor = Color.Black;
  @Event onChoose: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Text('Aa').fontSize(23).fontWeight(500).fontColor(this.inkColor)
          .width('100%').height(54).textAlign(TextAlign.Center)
          .backgroundColor(this.paperColor).borderRadius(14)
          .border({ width: this.selected ? 2 : 0.5,
            color: this.selected ? $r('app.color.primary') : this.palette.edge })
        Text(this.label).fontSize(12).fontWeight(this.selected ? 600 : 400)
          .fontColor(this.selected ? this.palette.text : this.palette.meta)
      }.width('100%')
    }
    .id('theme_' + this.keyName).width('100%').padding(2).backgroundColor(Color.Transparent)
    .borderRadius(14).accessibilityText(this.label + (this.selected ? '，已选择' : ''))
    .onClick(() => this.onChoose())
  }
}

/** Native sheet, buttons and toggle; application-owned typography and paper choices. */
@ComponentV2
export struct ReadingSettingsPanel {
  @Param palette: ReadingPalette = ThemeManager.WHITE;
  @Local assetBusy: boolean = false;
  @Param settings: ReadingSettings = new ReadingSettings();
  @Param wideWindow: boolean = false;
  @Param epub: boolean = false;
  @Param fixedLayout: boolean = false;
  @Event onFont: (delta: number) => void = () => {};
  @Event onLineHeight: (delta: number) => void = () => {};
  @Event onTheme: (theme: string) => void = () => {};
  @Event onLayoutMode: (mode: string) => void = () => {};
  @Event onReduceMotion: (value: boolean) => void = () => {};
  @Event onClose: () => void = () => {};

  private selectFont(choice: string): void {
    if (this.assetBusy) { return; }
    try { ReadingAssets.selectFont(this.settings, choice); }
    catch (e) { this.getUIContext().getPromptAction().showToast({ message: e instanceof Error ? e.message : '字体切换失败' }); }
  }

  private async chooseAsset(font: boolean, reset: boolean = false): Promise<void> {
    if (this.assetBusy) { return; }
    this.assetBusy = true;
    try {
      if (reset) { await ReadingAssets.reset(this.getUIContext(), this.settings, font); }
      else { await ReadingAssets.choose(this.getUIContext(), this.settings, font); }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: e instanceof Error ? e.message : '素材未能加载，请重试' });
    } finally { this.assetBusy = false; }
  }

  @Builder
  sectionLabel(label: string) {
    Text(label).fontSize(13).fontWeight(500).fontColor(this.palette.meta)
      .margin({ left: 4, bottom: 10 })
  }

  build() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text('阅读外观').fontSize(24).fontWeight(700).fontColor(this.palette.text)
          Text('让这一页，适合你').fontSize(13).fontColor(this.palette.meta)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        IconButton({ icon: $r('app.media.ic_close'), label: '关闭阅读设置', tint: this.palette.text, onAction: () => this.onClose() })
          .id('reading_settings_close')
      }.width('100%').padding({ left: 24, right: 16, top: 12, bottom: 24 })

      Scroll() {
        Column({ space: 24 }) {
          if (this.fixedLayout) {
            Text('这本书采用固定版式，按原页完整缩放；字号、字体和单双页重排不适用于此页。仍可调整阅读主题与背景。')
              .fontSize(14).lineHeight(23).fontColor(this.palette.meta)
          }
          if (this.epub && !this.fixedLayout) {
            Row({ space: 16 }) {
              Column({ space: 4 }) {
                Text('出版者排版').fontSize(16).fontColor(this.palette.text)
                Text('保留书内段落样式；自选字体优先，调节字号或行距时采用自定义排版。')
                  .fontSize(12).fontColor(this.palette.meta)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.settings.publisherStyle }).id('epub_publisher_style')
                .onChange((value: boolean) => { this.settings.publisherStyle = value; })
            }.width('100%').padding(16).backgroundColor(this.palette.bg).borderRadius(20)
          }
          if (!this.fixedLayout) {
          Column({ space: 12 }) {
            this.sectionLabel('字体')
            Row({ space: 10 }) {
              FontChoice({ palette: this.palette, keyName: 'default', label: this.epub ? '原书字体' : '默认',
                selected: ReadingFonts.choice(this.settings) === 'default', disabled: this.assetBusy,
                onChoose: () => this.selectFont('default') }).layoutWeight(1)
              FontChoice({ palette: this.palette, keyName: 'song', label: '宋体', family: 'ReadBooksSong',
                selected: ReadingFonts.choice(this.settings) === 'song', disabled: this.assetBusy,
                onChoose: () => this.selectFont('song') }).layoutWeight(1)
              FontChoice({ palette: this.palette, keyName: 'kai', label: '楷体', family: 'ReadBooksKai',
                selected: ReadingFonts.choice(this.settings) === 'kai', disabled: this.assetBusy,
                onChoose: () => this.selectFont('kai') }).layoutWeight(1)
            }.width('100%')
            Text('宋体 · 思源宋体　楷体 · 霞鹜文楷\n内置可离线使用，切换不会移除已导入的字体。')
              .fontSize(12).lineHeight(20).fontColor(this.palette.meta)
            if (this.settings.fontPath) {
              ReadingChoice({ palette: this.palette, keyName: 'font_custom', label: '自定义 · ' + (this.settings.fontName || '已导入字体').substring(0, 24),
                selected: ReadingFonts.choice(this.settings) === 'custom', disabled: this.assetBusy,
                onChoose: () => this.selectFont('custom') })
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
          Column() {
            this.sectionLabel('文字')
            Column() {
              TypeStepper({ palette: this.palette, label: '字号', keyName: 'reader_font', value: this.settings.fontSize,
                minimum: 17, maximum: 26, onStep: (delta: number) => this.onFont(delta) })
              Divider().color(this.palette.edge).margin({ left: 16, right: 16 })
              TypeStepper({ palette: this.palette, label: '行距', keyName: 'reader_line', value: this.settings.lineHeight,
                minimum: 1.4, maximum: 2, decimals: 2, onStep: (delta: number) => this.onLineHeight(delta * 0.05) })
            }.width('100%').backgroundColor(this.palette.bg).borderRadius(20)
          }.width('100%').alignItems(HorizontalAlign.Start)
          }

          Column() {
            this.sectionLabel('纸张与主题')
            Row({ space: 10 }) {
              ThemeChoice({ palette: this.palette, keyName: 'system', label: '跟随外观', selected: this.settings.theme === 'system',
                paperColor: $r('app.color.surface'), inkColor: $r('app.color.label_primary'),
                onChoose: () => this.onTheme('system') }).layoutWeight(1)
              ThemeChoice({ palette: this.palette, keyName: 'paper', label: '暖纸', selected: this.settings.theme === 'paper',
                paperColor: '#F7F2E7', inkColor: '#3A3A3C', onChoose: () => this.onTheme('paper') }).layoutWeight(1)
              ThemeChoice({ palette: this.palette, keyName: 'white', label: '纯白', selected: this.settings.theme === 'white',
                paperColor: '#FFFFFF', inkColor: '#202124', onChoose: () => this.onTheme('white') }).layoutWeight(1)
              ThemeChoice({ palette: this.palette, keyName: 'night', label: '夜间', selected: this.settings.theme === 'night',
                paperColor: '#141416', inkColor: '#DADADD', onChoose: () => this.onTheme('night') }).layoutWeight(1)
            }.width('100%')
            Text('跟随外观采用“我的”页面的深浅色设置。').fontSize(12)
              .fontColor(this.palette.meta).margin({ top: 12, left: 4 })
          }.width('100%').alignItems(HorizontalAlign.Start)

          if (!this.fixedLayout) {
          Column() {
            this.sectionLabel('页面布局')
            Row({ space: 4 }) {
              ReadingChoice({ palette: this.palette, label: '单页', keyName: 'layout_single', selected: this.settings.layoutMode === 'single' || !this.wideWindow,
                onChoose: () => this.onLayoutMode('single') }).layoutWeight(1)
              ReadingChoice({ palette: this.palette, label: '双页', keyName: 'layout_double', selected: this.settings.layoutMode === 'double' && this.wideWindow,
                disabled: !this.wideWindow, onChoose: () => this.onLayoutMode('double') }).layoutWeight(1)
            }.width('100%').padding(4).backgroundColor(this.palette.edge).borderRadius(16)
            Text(this.wideWindow ? '单页专注阅读，双页并排展开。' : '当前窗口显示单页，放大窗口或横屏后可使用双页。')
              .fontSize(12).fontColor(this.palette.meta).margin({ top: 12, left: 4 })
          }.width('100%').alignItems(HorizontalAlign.Start)
          }

          Column({ space: 12 }) {
            this.sectionLabel('个性化阅读')
            if (!this.fixedLayout) {
            Button('导入其他字体 · TTF / OTF')
              .id('reader_choose_font').width('100%').height(44).enabled(!this.assetBusy)
              .onClick(() => this.chooseAsset(true))
            if (this.settings.fontPath) {
              Button('移除导入的字体').id('reader_reset_font').width('100%').height(40).enabled(!this.assetBusy)
                .onClick(() => this.chooseAsset(true, true))
            }
            }
            Button(this.settings.backgroundPath ? '更换背景图片' : '选择背景图片')
              .id('reader_choose_background').width('100%').height(44).enabled(!this.assetBusy)
              .onClick(() => this.chooseAsset(false))
            if (this.settings.backgroundPath) {
              Row() {
                Text('背景浓度').fontSize(14).fontColor(this.palette.meta)
                Slider({ value: this.settings.backgroundOpacity, min: 0.05, max: 0.6, step: 0.05 }).layoutWeight(1)
                  .onChange((value: number) => { this.settings.backgroundOpacity = value; })
              }.width('100%')
              Button('移除背景图片').id('reader_reset_background').width('100%').height(40)
                .onClick(() => this.chooseAsset(false, true))
            }
          }.width('100%').alignItems(HorizontalAlign.Start)

          Row({ space: 16 }) {
            Column({ space: 4 }) {
              Text('减少动态效果').fontSize(16).fontColor(this.palette.text)
              Text('简化翻页和界面过渡').fontSize(12).fontColor(this.palette.meta)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.reduceMotion })
              .id('reduce_motion').accessibilityText('减少动态效果')
              .onChange((value: boolean) => this.onReduceMotion(value))
          }.width('100%').padding(16).backgroundColor(this.palette.bg).borderRadius(20)
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 24, right: 24, bottom: 32 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Auto).id('reading_settings_scroll')
    }.id('reading_settings_panel').width('100%').height('100%').backgroundColor(this.palette.chrome)
  }
}
