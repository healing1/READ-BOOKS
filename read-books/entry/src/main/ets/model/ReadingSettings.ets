import { PersistenceV2 } from '@kit.ArkUI';

/** 阅读设置 —— docs/DESIGN.md §6.2，PersistenceV2 自动持久化 */
@ObservedV2
export class ReadingSettings {
  @Trace fontSize: number = 18;      // fp，17-26
  @Trace lineHeight: number = 1.55;  // 1.4-2.0
  @Trace theme: string = 'system';   // system | paper | white | night
  @Trace pageMode: string = 'both';  // slide | tap | both
  @Trace layoutMode: string = 'double'; // single | double (narrow windows display one page)
  @Trace reduceMotion: boolean = false;
  @Trace fontPath: string = '';
  @Trace fontFamily: string = '';
  @Trace fontName: string = '';
  @Trace fontChoice: string = ''; // Empty migrates an existing custom font without changing it.
  @Trace backgroundPath: string = '';
  @Trace backgroundOpacity: number = 0.18;
  @Trace publisherStyle: boolean = true;

  static load(): ReadingSettings {
    const settings: ReadingSettings = PersistenceV2.connect(ReadingSettings, 'reading_settings',
      (): ReadingSettings => new ReadingSettings()) ?? new ReadingSettings();
    settings.fontSize = Number.isFinite(settings.fontSize) ? Math.max(17, Math.min(26, settings.fontSize)) : 18;
    settings.lineHeight = Number.isFinite(settings.lineHeight) ? Math.max(1.4, Math.min(2, settings.lineHeight)) : 1.55;
    if (['system', 'paper', 'white', 'night'].indexOf(settings.theme) < 0) {
      settings.theme = 'system';
    }
    // Both gestures are always available; migrate older one-mode preferences.
    settings.pageMode = 'both';
    if (typeof settings.fontPath !== 'string') { settings.fontPath = ''; }
    if (typeof settings.fontFamily !== 'string') { settings.fontFamily = ''; }
    if (typeof settings.fontName !== 'string') { settings.fontName = ''; }
    if (['default', 'song', 'kai', 'custom'].indexOf(settings.fontChoice) < 0) {
      settings.fontChoice = settings.fontPath ? 'custom' : 'default';
    }
    if (settings.fontChoice === 'custom' && !settings.fontPath) { settings.fontChoice = 'default'; }
    if (typeof settings.backgroundPath !== 'string') { settings.backgroundPath = ''; }
    if (typeof settings.publisherStyle !== 'boolean') { settings.publisherStyle = true; }
    settings.backgroundOpacity = Number.isFinite(settings.backgroundOpacity) ? Math.max(0.05, Math.min(0.6, settings.backgroundOpacity)) : 0.18;
    if (['single', 'double'].indexOf(settings.layoutMode) < 0) {
      settings.layoutMode = 'double';
    }
    return settings;
  }
}
