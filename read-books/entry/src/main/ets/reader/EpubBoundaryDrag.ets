import { TurnVelocity } from './PageTurnMotion';

/** A new contact should not restart a nearly finished chapter handoff. */
export function canPromoteSettlingChapter(commits: boolean, ready: boolean, offset: number, width: number): boolean {
  return commits && ready && width > 0 && Math.abs(offset) >= width * 0.72;
}

/** Window-coordinate gesture state. No DOM reads or chapter loading in the move path. */
export class EpubBoundaryDrag {
  down: boolean = false;
  boundary: boolean = false;
  delta: number = 0;
  side: number = 1;
  offset: number = 0;
  private x: number = 0;
  private y: number = 0;
  private page: number = 0;
  private pages: number = 1;
  private rtl: boolean = false;
  private width: number = 1;
  readonly velocity: TurnVelocity = new TurnVelocity();

  start(x: number, y: number, page: number, pages: number, rtl: boolean, width: number, now: number = Date.now()): void {
    this.reset(); this.down = true; this.x = x; this.y = y;
    this.page = page; this.pages = pages; this.rtl = rtl; this.width = Math.max(1, width);
    this.velocity.start(x, now);
  }
  move(x: number, y: number, now: number = Date.now()): boolean {
    if (!this.down) { return false; }
    this.velocity.sample(x, now);
    const dx = x - this.x; const dy = y - this.y;
    if (!this.boundary) {
      if (Math.abs(dx) < 10 || Math.abs(dx) <= Math.abs(dy) * 1.4) { return false; }
      const delta = (this.rtl ? dx > 0 : dx < 0) ? 1 : -1;
      if (this.page + delta >= 0 && this.page + delta < this.pages) { return false; }
      this.boundary = true; this.delta = delta; this.side = dx < 0 ? 1 : -1;
    }
    // Reversing beyond the starting point cancels, never turns the opposite page accidentally.
    this.offset = (-this.side * Math.max(0, Math.min(this.width, -this.side * dx))) || 0;
    return true;
  }
  commit(): boolean { return this.boundary && Math.abs(this.offset) > 55; }
  reset(): void { this.down = false; this.boundary = false; this.offset = 0; this.delta = 0; this.side = 1; }
}

/** Retain a fresh turn started during a native chapter settle, even if the surface
 * switches before Up. The root owns that entire contact; ArkWeb must not replay it. */
export class EpubFollowupInput {
  down: boolean = false;
  gap: number = 0;
  content: number = 0;
  readonly velocity: TurnVelocity = new TurnVelocity();
  private originGap: number = 0;
  private side: number = 1;
  private x: number = 0;
  private y: number = 0;
  private rtl: boolean = false;
  private width: number = 1;
  start(x: number, y: number, rtl: boolean, width: number, gap: number = 0, side: number = 1): void {
    this.down = true; this.x = x; this.y = y; this.rtl = rtl; this.width = Math.max(1, width);
    this.originGap = gap; this.gap = gap; this.side = side; this.content = 0;
    this.velocity.start(x, Date.now());
  }
  move(x: number, y: number): boolean {
    if (!this.down) { return false; }
    this.velocity.sample(x, Date.now());
    const dx = x - this.x; const dy = y - this.y;
    if (Math.abs(dx) < 10 || Math.abs(dx) <= Math.abs(dy) * 1.4) { return false; }
    const total = this.originGap + Math.max(-this.width, Math.min(this.width, dx));
    this.gap = this.side * Math.max(0, Math.min(this.width, this.side * total)) || 0;
    this.content = total - this.gap;
    return true;
  }
  finish(x: number, y: number): number {
    if (!this.down) { return 0; }
    this.down = false;
    const dx = x - this.x; const dy = y - this.y;
    if (Math.abs(dx) > 55 && Math.abs(dx) > Math.abs(dy) * 1.4) {
      return (this.rtl ? dx > 0 : dx < 0) ? 1 : -1;
    }
    if (Math.abs(dx) < 10 && Math.abs(dy) < 10) { return x < this.width * 0.2 ? -1 : x > this.width * 0.8 ? 1 : 0; }
    return 0;
  }
  reset(): void { this.down = false; this.gap = 0; this.content = 0; }
}
