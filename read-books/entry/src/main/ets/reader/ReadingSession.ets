import { ReadingActivityRepo } from '../data/ReadingActivityRepo';

/** Only foreground reading time counts; a suspended timer cannot add background hours. */
export class ReadingSession {
  private startedAt: number = 0;
  private lastInteraction: number = 0;
  private active: boolean = false;

  interact(): void {
    this.lastInteraction = Date.now();
  }

  resume(): void {
    if (!this.active) {
      this.startedAt = Date.now();
      this.lastInteraction = this.startedAt;
      this.active = true;
    }
  }

  async flush(): Promise<void> {
    if (!this.active) {
      return;
    }
    const now: number = Date.now();
    const end: number = Math.min(now, this.startedAt + 35000, this.lastInteraction + 5 * 60 * 1000);
    const start: number = this.startedAt;
    this.startedAt = now;
    if (end > start) {
      await ReadingActivityRepo.recordInterval(start, end);
    }
  }

  async pause(): Promise<void> {
    const saving: Promise<void> = this.flush();
    this.active = false;
    await saving;
  }
}
