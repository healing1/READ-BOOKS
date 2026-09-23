import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { UIContext, PersistenceV2 } from '@kit.ArkUI';
import { text } from '@kit.ArkGraphics2D';
import { ReadingSettings } from '../model/ReadingSettings';
import { CoverStore } from './CoverStore';

/** Copies only a user-selected asset; original image/font files are never changed. */
export class ReadingAssets {
  private static sequence: number = 0;
  private static registeredFonts: Set<string> = new Set<string>();
  private static registerCustom(family: string, path: string): void {
    if (ReadingAssets.registeredFonts.has(family)) { return; }
    text.FontCollection.getGlobalInstance().loadFontSync(family, 'file://' + path);
    ReadingAssets.registeredFonts.add(family);
  }
  static selectFont(settings: ReadingSettings, choice: string): void {
    if (['default', 'song', 'kai', 'custom'].indexOf(choice) < 0 || (choice === 'custom' && !settings.fontPath)) {
      throw new Error('请选择可用字体');
    }
    const previous: string = settings.fontChoice;
    settings.fontChoice = choice;
    try { PersistenceV2.save('reading_settings'); }
    catch (_) { settings.fontChoice = previous; throw new Error('字体选择未能保存，请重试'); }
  }
  static register(ui: UIContext, settings: ReadingSettings): void {
    if (settings.fontPath && settings.fontFamily && fs.accessSync(settings.fontPath)) {
      ReadingAssets.registerCustom(settings.fontFamily, settings.fontPath);
    }
  }
  static async choose(ui: UIContext, settings: ReadingSettings, font: boolean): Promise<void> {
    const context = ui.getHostContext() as common.UIAbilityContext;
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = font ? ['字体|.ttf,.otf'] : ['背景图片|.png,.jpg,.jpeg'];
    const selected = await new picker.DocumentViewPicker(context).select(options);
    if (selected.length === 0) { return; }
    await ReadingAssets.importSelected(ui, settings, font, selected[0]);
  }
  static async importSelected(ui: UIContext, settings: ReadingSettings, font: boolean, uri: string): Promise<void> {
    const context = ui.getHostContext() as common.UIAbilityContext;
    const bytes: Uint8Array = font ? await ReadingAssets.readFont(uri) : await CoverStore.readImage(uri, true);
    const directory: string = context.filesDir + '/reading_assets';
    if (!fs.accessSync(directory)) { fs.mkdirSync(directory); }
    const family: string = 'ReaderCustom_' + Date.now() + '_' + ReadingAssets.sequence++;
    const path: string = directory + '/' + family + (font ? '.font' : '.png');
    const old: string = font ? settings.fontPath : settings.backgroundPath;
    const oldFamily: string = settings.fontFamily;
    const oldName: string = settings.fontName;
    const oldChoice: string = settings.fontChoice;
    try {
    const file = await fs.open(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      let offset: number = 0;
      while (offset < bytes.length) {
        const chunk = bytes.slice(offset, Math.min(bytes.length, offset + 128 * 1024));
        const count = await fs.write(file.fd, chunk.buffer);
        if (count <= 0) { throw new Error('保存阅读素材失败'); }
        offset += count;
      }
      await fs.fsync(file.fd);
    } finally { await fs.close(file); }
    await fs.rename(path + '.tmp', path);
    if (font) {
      ReadingAssets.registerCustom(family, path);
      settings.fontPath = path; settings.fontFamily = family;
      let name: string = uri.substring(uri.lastIndexOf('/') + 1);
      try { name = decodeURIComponent(name); } catch (_) {}
      settings.fontName = name.substring(0, 80);
      settings.fontChoice = 'custom';
    } else { settings.backgroundPath = path; }
    PersistenceV2.save('reading_settings');
    } catch (e) {
      if (font) { settings.fontPath = old; settings.fontFamily = oldFamily; settings.fontName = oldName; settings.fontChoice = oldChoice; }
      else { settings.backgroundPath = old; }
      await ReadingAssets.removeOwned(context, path);
      await ReadingAssets.removeOwned(context, path + '.tmp');
      throw e instanceof Error ? e : new Error('保存阅读素材失败');
    }
    await ReadingAssets.removeOwned(context, old);
  }
  static async reset(ui: UIContext, settings: ReadingSettings, font: boolean): Promise<void> {
    const old: string = font ? settings.fontPath : settings.backgroundPath;
    const family: string = settings.fontFamily;
    const name: string = settings.fontName;
    const choice: string = settings.fontChoice;
    if (font) {
      settings.fontPath = ''; settings.fontFamily = ''; settings.fontName = '';
      if (choice === 'custom' || choice === '') { settings.fontChoice = 'default'; }
    } else { settings.backgroundPath = ''; }
    try { PersistenceV2.save('reading_settings'); }
    catch (e) {
      if (font) { settings.fontPath = old; settings.fontFamily = family; settings.fontName = name; settings.fontChoice = choice; }
      else { settings.backgroundPath = old; }
      throw new Error('设置保存失败，原素材已保留');
    }
    await ReadingAssets.removeOwned(ui.getHostContext() as common.UIAbilityContext, old);
  }
  private static async removeOwned(context: common.UIAbilityContext, path: string): Promise<void> {
    const prefix: string = context.filesDir + '/reading_assets/';
    if (!path.startsWith(prefix) || !/^ReaderCustom_[0-9]+_[0-9]+\.(font|png)(\.tmp)?$/.test(path.substring(prefix.length))) { return; }
    try { if (fs.accessSync(path)) { await fs.unlink(path); } } catch (_) {}
  }
  private static async readFont(uri: string): Promise<Uint8Array> {
    const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const before = await fs.stat(file.fd);
      const size: number = before.size;
      if (!Number.isSafeInteger(size) || size < 12 || size > 64 * 1024 * 1024) { throw new Error('请选择 64 MiB 以内的 TTF 或 OTF 字体'); }
      const bytes = new Uint8Array(size);
      let offset: number = 0;
      while (offset < size) {
        const chunk = new ArrayBuffer(Math.min(128 * 1024, size - offset));
        const count = await fs.read(file.fd, chunk);
        if (count <= 0) { throw new Error('字体文件不完整'); }
        bytes.set(new Uint8Array(chunk, 0, count), offset); offset += count;
      }
      const signature = new DataView(bytes.buffer).getUint32(0);
      const after = await fs.stat(file.fd);
      if (after.size !== before.size || after.mtime !== before.mtime) { throw new Error('字体文件已变化，请重试'); }
      if (signature !== 0x00010000 && signature !== 0x4F54544F && signature !== 0x74727565) {
        throw new Error('文件不是有效的 TTF / OTF 字体');
      }
      const view = new DataView(bytes.buffer);
      const tables = view.getUint16(4);
      if (tables < 1 || tables > 4096 || 12 + tables * 16 > bytes.length) { throw new Error('字体目录损坏'); }
      const names: Set<number> = new Set<number>();
      for (let i: number = 0; i < tables; i++) {
        const start = 12 + i * 16;
        const tag = view.getUint32(start);
        const offset = view.getUint32(start + 8);
        const length = view.getUint32(start + 12);
        if (names.has(tag) || offset > bytes.length || length > bytes.length - offset) { throw new Error('字体数据不完整'); }
        names.add(tag);
      }
      if (!names.has(0x636D6170) || !names.has(0x68656164)) { throw new Error('字体缺少必要的字形映射'); }
      return bytes;
    } finally { await fs.close(file); }
  }
}
