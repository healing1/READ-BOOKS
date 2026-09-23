/** Per-open-book LRU. No disk copies, no cross-book keys; release everything when the reader closes. */
export class EpubResourceCache {
  private items: Map<string, Uint8Array> = new Map<string, Uint8Array>();
  private bytes: number = 0;
  private limit: number;
  private countLimit: number;
  constructor(limit: number = 64 * 1024 * 1024, countLimit: number = 128) {
    this.limit = limit; this.countLimit = countLimit;
  }
  get(key: string): Uint8Array | undefined {
    const value = this.items.get(key);
    if (value !== undefined) { this.items.delete(key); this.items.set(key, value); }
    return value;
  }
  put(key: string, value: Uint8Array): void {
    const prior = this.items.get(key);
    if (prior !== undefined) { this.bytes -= prior.byteLength; this.items.delete(key); }
    if (value.byteLength > this.limit || this.countLimit < 1) { return; }
    while (this.items.size && (this.bytes + value.byteLength > this.limit || this.items.size >= this.countLimit)) {
      const oldest: string = this.items.keys().next().value;
      this.bytes -= this.items.get(oldest)!.byteLength; this.items.delete(oldest);
    }
    this.items.set(key, value); this.bytes += value.byteLength;
  }
  clear(): void { this.items.clear(); this.bytes = 0; }
  retain(keys: string[]): void {
    const keep = new Set<string>(keys);
    for (const key of this.items.keys()) {
      if (!keep.has(key)) { this.bytes -= this.items.get(key)!.byteLength; this.items.delete(key); }
    }
  }
  sizeBytes(): number { return this.bytes; }
  count(): number { return this.items.size; }
}
