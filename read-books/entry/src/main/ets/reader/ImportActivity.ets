import { fileIo as fs } from '@kit.CoreFileKit';

/** Shared by all formats so recovery never removes a file being imported. */
export class ImportActivity {
  private static paths: Set<string> = new Set<string>();
  private static sequence: number = 0;

  static reserve(directory: string, extension: string): string {
    if (['txt', 'pdf', 'epub'].indexOf(extension) < 0) {
      throw new Error('不支持的图书文件类型');
    }
    let path: string = '';
    do {
      path = directory + '/book_' + Date.now() + '_' + ImportActivity.sequence++ + '.' + extension;
    } while (fs.accessSync(path) || fs.accessSync(path + '.tmp') || ImportActivity.has(path));
    ImportActivity.add(path);
    ImportActivity.add(path + '.tmp');
    return path;
  }

  static add(path: string): void { ImportActivity.paths.add(path); }
  static reserveCover(directory: string): string {
    let path: string = '';
    do {
      path = directory + '/book_' + Date.now() + '_' + ImportActivity.sequence++ + '_cover.png';
    } while (fs.accessSync(path) || fs.accessSync(path + '.tmp') || ImportActivity.has(path));
    ImportActivity.add(path);
    ImportActivity.add(path + '.tmp');
    return path;
  }

  static remove(path: string): void { ImportActivity.paths.delete(path); }
  static has(path: string): boolean { return ImportActivity.paths.has(path); }
}
