import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { text } from '@kit.ArkGraphics2D';
import { Db } from '../data/Db';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Db.init(this.context).catch((error: Error) => {
      hilog.error(0x0000, TAG, 'Database startup failed: %{public}s', error.message);
    });
    hilog.info(0x0000, TAG, 'READ BOOKS ability created');
  }

  onDestroy(): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Bookshelf', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, TAG, 'loadContent succeed');
      const fonts = windowStage.getMainWindowSync().getUIContext().getFont();
      fonts.registerFont({ familyName: 'DM Sans', familySrc: $rawfile('fonts/DMSans.ttf') });
      fonts.registerFont({ familyName: 'JetBrains Mono', familySrc: $rawfile('fonts/JetBrainsMono.ttf') });
      // Canvas and Text share the global font collection. Register once, before reader measurement.
      try {
        const collection = text.FontCollection.getGlobalInstance();
        collection.loadFontSync('ReadBooksSong', $rawfile('fonts/SourceHanSerifSC-Regular.otf'));
        collection.loadFontSync('ReadBooksKai', $rawfile('fonts/LXGWWenKai-Regular.ttf'));
      } catch (error) {
        hilog.error(0x0000, TAG, 'Reading font registration failed');
      }
    });
  }

  onForeground(): void {
  }

  onBackground(): void {
  }
}
