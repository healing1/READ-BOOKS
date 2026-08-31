/**
 * 阅读主题 —— docs/DESIGN.md §3.2 阅读主题表
 * Canvas 自绘需要运行期具体色值，不走资源表；UI 层仍用 $r 语义色
 */
export class ReadingPalette {
  readonly bg: string;
  readonly text: string;
  readonly meta: string;

  constructor(bg: string, text: string, meta: string) {
    this.bg = bg;
    this.text = text;
    this.meta = meta;
  }
}

export class ThemeManager {
  static readonly WHITE: ReadingPalette = new ReadingPalette('#FFFFFF', '#000000', '#8E8E93');
  static readonly PAPER: ReadingPalette = new ReadingPalette('#F7F2E7', '#3A3A3C', '#8E8E93');
  static readonly NIGHT: ReadingPalette = new ReadingPalette('#000000', '#AEAEB2', '#6E6E73');

  static resolve(theme: string, dark: boolean): ReadingPalette {
    if (theme === 'paper') {
      return ThemeManager.PAPER;
    }
    if (theme === 'night') {
      return ThemeManager.NIGHT;
    }
    if (theme === 'white') {
      return ThemeManager.WHITE;
    }
    return dark ? new ReadingPalette('#000000', '#F5F5F7', '#8E8E93') : ThemeManager.WHITE;
  }
}
