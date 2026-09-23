/** Based on the actual app window, so split-screen is not mistaken for a tablet. */
export class ShelfLayout {
  static readonly WIDE: number = 840;
  static readonly MAX_WIDTH: number = 1440;
  static inset(width: number): number { return width >= 1200 ? 48 : width >= 600 ? 32 : 20; }
  static columns(width: number): number {
    const content: number = Math.min(ShelfLayout.MAX_WIDTH, width) - ShelfLayout.inset(width) * 2;
    return Math.max(2, Math.min(6, Math.ceil((content + 24) / 224)));
  }
  static contentWidth(width: number): number { return Math.min(ShelfLayout.MAX_WIDTH, width); }
}
