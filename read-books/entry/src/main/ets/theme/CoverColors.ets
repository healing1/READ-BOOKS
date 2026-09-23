/** Palette extraction works on a tiny RGBA thumbnail; whites/blacks don't overwhelm the cover's ink. */
export class CoverColors {
  static dominant(rgba: Uint8Array, fallback: string): string {
    const weights: Map<number, number> = new Map<number, number>();
    for (let i: number = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 128) { continue; }
      const r: number = rgba[i], g: number = rgba[i + 1], b: number = rgba[i + 2];
      const max: number = Math.max(r, g, b), min: number = Math.min(r, g, b);
      if (max < 24 || min > 235) { continue; }
      const key: number = (r >> 5) * 64 + (g >> 5) * 8 + (b >> 5);
      weights.set(key, (weights.get(key) ?? 0) + 1 + (max - min) / 70);
    }
    let best: number = -1, score: number = 0;
    weights.forEach((value: number, key: number) => { if (value > score) { score = value; best = key; } });
    return best < 0 ? fallback : CoverColors.hex((best >> 6) * 32 + 16, ((best >> 3) & 7) * 32 + 16, (best & 7) * 32 + 16);
  }
  static hex(r: number, g: number, b: number): string {
    return '#' + [r, g, b].map((c: number) => Math.max(0, Math.min(255, Math.round(c))).toString(16).padStart(2, '0')).join('');
  }
  static surface(tone: string, dark: boolean, end: boolean = false): string {
    const safe: string = /^#[0-9a-f]{6}$/i.test(tone) ? tone : '#677D91';
    const amount: number = dark ? (end ? 0.40 : 0.24) : (end ? 0.30 : 0.12);
    const base: number = dark ? 20 : 255;
    const values: number[] = [1, 3, 5].map((at: number) => base * (1 - amount) + parseInt(safe.substring(at, at + 2), 16) * amount);
    return CoverColors.hex(values[0], values[1], values[2]);
  }
}
