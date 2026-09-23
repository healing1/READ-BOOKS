/**
 * 阅读主题 —— docs/DESIGN.md §3.2 阅读主题表
 * Canvas 自绘需要运行期具体色值，不走资源表；UI 层仍用 $r 语义色
 */
export class ReadingPalette {
  readonly bg: string;
  readonly text: string;
  readonly meta: string;
  readonly chrome: string;
  readonly edge: string;

  constructor(bg: string, text: string, meta: string) {
    this.bg = bg;
    this.text = text;
    this.meta = meta;
    this.chrome = bg === '#F7F2E7' ? '#F0E7D7' : bg === '#141416' ? '#252528' : '#F3F3F5';
    this.edge = bg === '#141416' ? '#505056' : bg === '#F7F2E7' ? '#D9CBB5' : '#D8D8DE';
  }
}

export class ThemeManager {
  static chromeDark(theme: string, dark: boolean, appearance: string = 'system'): boolean {
    return theme === 'night' || (theme !== 'paper' && theme !== 'white' && ThemeManager.effectiveDark(appearance, dark));
  }
  static effectiveDark(appearance: string, systemDark: boolean): boolean {
    return appearance === 'dark' || (appearance !== 'light' && systemDark);
  }
  static readonly WHITE: ReadingPalette = new ReadingPalette('#FFFFFF', '#000000', '#8E8E93');
  static readonly PAPER: ReadingPalette = new ReadingPalette('#F7F2E7', '#3A3A3C', '#8E8E93');
  static readonly NIGHT: ReadingPalette = new ReadingPalette('#141416', '#DADADD', '#8E8E93');

  static resolve(theme: string, dark: boolean, appearance: string = 'system'): ReadingPalette {
    if (theme === 'paper') {
      return ThemeManager.PAPER;
    }
    if (theme === 'night') {
      return ThemeManager.NIGHT;
    }
    if (theme === 'white') {
      return ThemeManager.WHITE;
    }
    return ThemeManager.effectiveDark(appearance, dark) ? ThemeManager.NIGHT : ThemeManager.WHITE;
  }
}
