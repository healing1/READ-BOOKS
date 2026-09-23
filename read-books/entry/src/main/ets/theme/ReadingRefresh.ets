import { display } from '@kit.ArkUI';
import { displaySync } from '@kit.ArkGraphics2D';

/** No fixed 60/120 cap: only request rates reported by this display. */
export function readingFrameRange(current: number, supported: number[] = []): ExpectedFrameRateRange {
  let peak: number = Number.isFinite(current) && current > 0 ? Math.round(current) : 0;
  for (const rate of supported) {
    if (Number.isFinite(rate) && rate > 0) { peak = Math.max(peak, Math.round(rate)); }
  }
  return { min: 0, max: peak, expected: peak };
}

/** A short-lived vsync subscription for direct finger tracking; never runs while reading at rest. */
export class ReadingRefresh {
  private sync: displaySync.DisplaySync | null = null;
  private timer: number = -1;
  private live: boolean = false;
  private frame: () => void;
  constructor(frame: () => void = () => {}) { this.frame = frame; }

  static range(): ExpectedFrameRateRange {
    try {
      const screen = display.getDefaultDisplaySync();
      return readingFrameRange(screen.refreshRate, screen.supportedRefreshRates ?? []);
    } catch (_) { return { min: 0, max: 0, expected: 0 }; }
  }
  get running(): boolean { return this.live; }
  begin(reduced: boolean): void {
    clearTimeout(this.timer);
    if (reduced) { this.stop(); return; }
    if (this.live) { return; }
    try {
      if (!this.sync) {
        this.sync = displaySync.create();
        this.sync.on('frame', () => { if (this.live) { this.frame(); } });
      }
      this.sync.setExpectedFrameRateRange(ReadingRefresh.range());
      this.live = true;
      this.sync.start();
    } catch (_) { this.stop(); }
  }
  end(): void {
    clearTimeout(this.timer);
    // Keep the vote for the short release animation, then let the system idle normally.
    if (this.live) { this.timer = setTimeout(() => this.stop(), 360); }
  }
  stop(): void {
    clearTimeout(this.timer); this.live = false;
    try { this.sync?.stop(); } catch (_) {}
  }
  dispose(): void {
    this.stop();
    try { this.sync?.off('frame'); } catch (_) {}
    this.sync = null;
  }
}
