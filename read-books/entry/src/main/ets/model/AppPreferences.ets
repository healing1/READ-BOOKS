import { PersistenceV2 } from '@kit.ArkUI';

@ObservedV2
export class AppPreferences {
  @Trace dailyMinutes: number = 30;
  @Trace yearlyBooks: number = 5;
  @Trace appearance: string = 'dark';
  @Trace libraryLayout: string = 'grid';
  @Trace librarySort: string = 'recent';
  @Trace username: string = '书友';
  @Trace avatarPath: string = '';

  static load(): AppPreferences {
    const value = PersistenceV2.connect(AppPreferences, 'app_preferences',
      (): AppPreferences => new AppPreferences()) ?? new AppPreferences();
    value.dailyMinutes = Number.isFinite(value.dailyMinutes) ? Math.max(5, Math.min(240, value.dailyMinutes)) : 30;
    value.yearlyBooks = Number.isFinite(value.yearlyBooks) ? Math.max(1, Math.min(100, value.yearlyBooks)) : 5;
    if (['dark', 'light', 'system'].indexOf(value.appearance) < 0) {
      value.appearance = 'dark';
    }
    value.username = AppPreferences.cleanName(value.username);
    if (typeof value.avatarPath !== 'string') { value.avatarPath = ''; }
    return value;
  }

  static cleanName(value: string): string {
    return typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 20) || '书友' : '书友';
  }
}
