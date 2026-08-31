import { PersistenceV2 } from '@kit.ArkUI';

/** 阅读设置 —— docs/DESIGN.md §6.2，PersistenceV2 自动持久化 */
@ObservedV2
export class ReadingSettings {
  @Trace fontSize: number = 18;      // fp，17-26
  @Trace lineHeight: number = 1.55;  // 1.4-2.0
  @Trace theme: string = 'system';   // system | paper | white | night
  @Trace pageMode: string = 'both';  // slide | tap | both

  static load(): ReadingSettings {
    return PersistenceV2.connect(ReadingSettings, 'reading_settings', (): ReadingSettings => new ReadingSettings());
  }
}
