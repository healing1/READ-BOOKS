/** Four live documents: current, previous and two chapters ahead. */
export class EpubRenderSlot {
  path: string = '';
  token: string = '';
  index: number = -1;
  revision: number = 0;
  version: number = -1;
  attached: boolean = false;
  loaded: boolean = false;
  ready: boolean = false;
  page: number = 0;
  pages: number = 1;
  element: number = -1;
  fraction: number = 0;
  vertical: boolean = false;
  rtl: boolean = false;
  selected: boolean = false;
  fragment: string = '';
  target: string = 'null';
  anchor: string = '';
  startedAt: number = 0;
}

export class EpubRenderPool {
  slots: EpubRenderSlot[] = [new EpubRenderSlot(), new EpubRenderSlot(), new EpubRenderSlot(), new EpubRenderSlot()];
  current: number = -1;
  pending: number = -1;
  find(path: string): number { return this.slots.findIndex((slot: EpubRenderSlot) => slot.path === path); }
  reserve(path: string, index: number, keep: string[] = []): number {
    const existing: number = this.slots.findIndex((slot: EpubRenderSlot, id: number) => id !== this.current && slot.path === path);
    // Never navigate the visible surface, including a same-chapter TOC/progress jump.
    if (existing >= 0 && existing !== this.current) { return existing; }
    let chosen: number = -1;
    let distance: number = -1;
    for (let id: number = 0; id < this.slots.length; id++) {
      if (id === this.current || id === this.pending) { continue; }
      const slot: EpubRenderSlot = this.slots[id];
      if (keep.indexOf(slot.path) >= 0) { continue; }
      const score: number = slot.path ? Math.abs(slot.index - index) : Number.MAX_SAFE_INTEGER;
      if (score > distance) { chosen = id; distance = score; }
    }
    return chosen;
  }
  invalidate(): void { for (const slot of this.slots) { slot.version = -1; slot.ready = false; } }
}
