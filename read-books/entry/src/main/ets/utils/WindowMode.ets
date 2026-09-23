import { window } from '@kit.ArkUI';

/** All Reader instances share one queue: an older exit cannot race a newer entry. */
export class WindowMode {
  private static pending: Promise<void> = Promise.resolve();

  static setReaderMode(win: window.Window, enabled: boolean): Promise<void> {
    const operation = WindowMode.pending.catch(() => {}).then(async () => {
      if (enabled) {
        await win.setWindowLayoutFullScreen(true);
        await win.setWindowSystemBarEnable([]);
      } else {
        await win.setWindowSystemBarEnable(['status', 'navigation']);
        await win.setWindowLayoutFullScreen(false);
      }
    });
    WindowMode.pending = operation;
    return operation;
  }
}
