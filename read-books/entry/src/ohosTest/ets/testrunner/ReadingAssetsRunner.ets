import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { window, PersistenceV2 } from '@kit.ArkUI';
import { ReadingSettings } from '../../../main/ets/model/ReadingSettings';
import { ReadingAssets } from '../../../main/ets/reader/ReadingAssets';

class AssetSnapshot {
  previous: ReadingSettings = new ReadingSettings();
  font: string = '';
  background: string = '';
}
async function write(path: string, bytes: Uint8Array): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    let offset: number = 0;
    while (offset < bytes.length) {
      const count = await fs.write(file.fd, bytes.slice(offset).buffer);
      if (count <= 0) { throw new Error('QA write failed'); }
      offset += count;
    }
    await fs.fsync(file.fd);
  } finally { await fs.close(file); }
}

/** Explicit emulator-only asset smoke test. Restore only the exact assets this runner applied. */
export default class ReadingAssetsRunner implements TestRunner {
  onPrepare(): void {}
  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    if (deviceInfo.productModel.toLowerCase() !== 'emulator') { await delegator.finishTest('Emulator only', 1); return; }
    try {
      const parameters = abilityDelegatorRegistry.getArguments().parameters;
      const mode = parameters['assets'] ?? parameters['-s assets'];
      if (mode !== 'apply' && mode !== 'restore' && mode !== 'export' && mode !== 'cleanup') { throw new Error('Expected assets apply, restore, export or cleanup'); }
      const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility' };
      await delegator.addAbilityMonitor(monitor);
      await delegator.startAbility({ bundleName: 'com.healing1.readbooks', abilityName: 'EntryAbility' });
      const ability = await delegator.waitAbilityMonitor(monitor, 10000);
      await delegator.removeAbilityMonitor(monitor);
      const context = ability.context;
      if (mode === 'cleanup') {
        const backup = context.cacheDir + '/qa_reading_assets_snapshot.json';
        const snapshot = JSON.parse(await fs.readText(backup)) as AssetSnapshot;
        const prefix = context.filesDir + '/reading_assets/';
        for (const path of [snapshot.font, snapshot.background]) {
          if (!path.startsWith(prefix) || !/^ReaderCustom_[0-9]+_[0-9]+\.(font|png)$/.test(path.substring(prefix.length))) {
            throw new Error('Snapshot path is not a QA-owned asset');
          }
        }
        for (const path of [snapshot.font, snapshot.background]) { if (fs.accessSync(path)) { await fs.unlink(path); } }
        await fs.unlink(backup);
        await delegator.finishTest('QA_ASSETS_REMOVED', 0); return;
      }
      // Ability creation precedes the first native window on a cold emulator.
      for (let attempt: number = 0; attempt < 30; attempt++) {
        try { await window.getLastWindow(context); break; }
        catch (_) { await new Promise<void>((resolve) => { setTimeout(resolve, 100); }); }
      }
      const ui = (await window.getLastWindow(context)).getUIContext();
      if (mode === 'export') {
        const resources = delegator.getAppContext().createModuleContext('entry_test').resourceManager;
        const options = new picker.DocumentSaveOptions();
        options.newFileNames = ['Reading-QA.ttf', 'reading-background.png'];
        const destinations = await new picker.DocumentViewPicker(context).save(options);
        if (destinations.length !== 2) { throw new Error('Export cancelled'); }
        await write(destinations[0], await resources.getRawFileContent('formats/Reading-QA.ttf'));
        await write(destinations[1], await resources.getRawFileContent('formats/reading-background.png'));
        await delegator.finishTest('ASSETS_EXPORTED', 0); return;
      }
      const settings = ReadingSettings.load();
      const backup = context.cacheDir + '/qa_reading_assets_snapshot.json';
      if (mode === 'apply') {
        if (settings.fontPath || settings.backgroundPath || fs.accessSync(backup)) { throw new Error('Existing custom assets or snapshot present; nothing replaced'); }
        const snapshot = new AssetSnapshot();
        snapshot.previous = JSON.parse(JSON.stringify(settings)) as ReadingSettings;
        const resources = delegator.getAppContext().createModuleContext('entry_test').resourceManager;
        const fontPath = context.cacheDir + '/qa-custom-font.ttf';
        const backgroundPath = context.cacheDir + '/qa-custom-background.png';
        await write(fontPath, await resources.getRawFileContent('formats/Reading-QA.ttf'));
        await write(backgroundPath, await resources.getRawFileContent('formats/reading-background.png'));
        try {
          await ReadingAssets.importSelected(ui, settings, true, fontPath);
          snapshot.font = settings.fontPath;
          await ReadingAssets.importSelected(ui, settings, false, backgroundPath);
          snapshot.background = settings.backgroundPath;
          settings.backgroundOpacity = 0.25;
          PersistenceV2.save('reading_settings');
          await write(backup, util.TextEncoder.create('utf-8').encodeInto(JSON.stringify(snapshot)));
        } finally { await fs.unlink(fontPath); await fs.unlink(backgroundPath); }
        await delegator.finishTest('ASSETS_APPLIED:' + settings.fontName + ':' + fs.accessSync(settings.fontPath) + ':' + fs.accessSync(settings.backgroundPath), 0);
      } else {
        const snapshot = JSON.parse(await fs.readText(backup)) as AssetSnapshot;
        if (settings.fontPath !== snapshot.font || settings.backgroundPath !== snapshot.background) { throw new Error('Assets changed since QA; restore skipped'); }
        await ReadingAssets.reset(ui, settings, true);
        await ReadingAssets.reset(ui, settings, false);
        settings.backgroundOpacity = snapshot.previous.backgroundOpacity;
        settings.theme = snapshot.previous.theme;
        settings.fontSize = snapshot.previous.fontSize;
        settings.lineHeight = snapshot.previous.lineHeight;
        settings.layoutMode = snapshot.previous.layoutMode;
        settings.publisherStyle = snapshot.previous.publisherStyle;
        PersistenceV2.save('reading_settings');
        await fs.unlink(backup);
        await delegator.finishTest('ASSETS_RESTORED', 0);
      }
    } catch (e) { await delegator.finishTest(e instanceof Error ? e.message : 'Asset test failed', 1); }
  }
}
