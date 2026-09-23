export class PageSettle {
  duration: number = 0;
  firstY: number = 0;
}

/** Distance/velocity in the same coordinate system (vp or CSS px), time in ms.
 * Keep this small policy in parity with pageSettle in the injected EPUB engine. */
export function pageSettle(distance: number, span: number, velocity: number | null = null): PageSettle {
  const result = new PageSettle();
  const remaining = Math.abs(distance);
  if (remaining < 0.5) { return result; }
  const fraction = Math.min(1, remaining / Math.max(1, span));
  const ceiling = 200 + 120 * Math.sqrt(fraction);
  const floor = 160 + 60 * Math.sqrt(fraction);
  const speed = velocity === null ? 0 : Math.max(0, Math.sign(distance) * velocity);
  result.duration = Math.round(speed > 0.05 ? Math.max(floor, ceiling / (1 + speed * 60 / Math.max(1, span))) : ceiling);
  // Preserve finger tracking, but cap the release acceleration: fast input must not
  // collapse a full page into an 80 ms flash. No overshoot or long spring tail.
  result.firstY = velocity === null ? 0.28 : Math.min(0.4, speed * result.duration / remaining * 0.2);
  return result;
}

export class TurnVelocity {
  value: number = 0;
  private x: number = 0;
  private time: number = 0;
  private movedAt: number = 0;
  start(x: number, now: number): void { this.x = x; this.time = now; this.movedAt = now; this.value = 0; }
  sample(x: number, now: number): void {
    const elapsed = now - this.time;
    if (elapsed <= 0) { return; }
    if (x !== this.x) {
      const speed = elapsed > 100 ? 0 : (x - this.x) / elapsed;
      this.value = this.value * speed > 0 ? this.value * 0.35 + speed * 0.65 : speed;
      this.x = x; this.time = now; this.movedAt = now;
    } else if (now - this.movedAt > 80) { this.value = 0; this.time = now; }
  }
}
