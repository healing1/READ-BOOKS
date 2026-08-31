import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** SQLite —— docs/DESIGN.md §6.1 */
const DDL: string[] = [
  'CREATE TABLE IF NOT EXISTS books (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'title TEXT NOT NULL, author TEXT, format TEXT, size_bytes INTEGER, encoding TEXT, ' +
    'char_count INTEGER, cover_color TEXT, file_path TEXT, ' +
    'created_at INTEGER, last_read_at INTEGER, ' +
    'progress_char_offset INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
  'CREATE TABLE IF NOT EXISTS chapters (' +
    'book_id INTEGER, idx INTEGER, title TEXT, ' +
    'start_offset INTEGER, end_offset INTEGER, ' +
    'PRIMARY KEY (book_id, idx))',
  'CREATE TABLE IF NOT EXISTS bookmarks (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER, char_offset INTEGER, ' +
    'excerpt TEXT, created_at INTEGER)'
];

export class Db {
  private static store: relationalStore.RdbStore | null = null;
  private static initPromise: Promise<relationalStore.RdbStore> | null = null;

  static init(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
    if (Db.initPromise !== null) {
      return Db.initPromise;
    }
    const config: relationalStore.StoreConfig = {
      name: 'readbooks.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    Db.initPromise = new Promise<relationalStore.RdbStore>((resolve, reject) => {
      relationalStore.getRdbStore(context, config).then((store: relationalStore.RdbStore) => {
        const runDdl = async (): Promise<void> => {
          for (let i = 0; i < DDL.length; i++) {
            await store.executeSql(DDL[i]);
          }
          Db.store = store;
          resolve(store);
        };
        runDdl().catch((err: Error) => {
          reject(err);
        });
      }).catch((err: Error) => {
        reject(err);
      });
    });
    return Db.initPromise;
  }

  static async get(): Promise<relationalStore.RdbStore> {
    if (Db.store !== null) {
      return Db.store;
    }
    if (Db.initPromise !== null) {
      return Db.initPromise;
    }
    throw new Error('Db not initialized');
  }
}
