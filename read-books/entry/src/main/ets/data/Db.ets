import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** SQLite —— docs/DESIGN.md §6.1 */
const DDL: string[] = [
  'CREATE TABLE IF NOT EXISTS books (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'title TEXT NOT NULL, author TEXT, format TEXT, size_bytes INTEGER, encoding TEXT, ' +
    'char_count INTEGER, cover_color TEXT, cover_path TEXT DEFAULT \'\', file_path TEXT, ' +
    'created_at INTEGER, last_read_at INTEGER, ' +
    'progress_char_offset INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
  'CREATE TABLE IF NOT EXISTS chapters (' +
    'book_id INTEGER, idx INTEGER, title TEXT, ' +
    'start_offset INTEGER, end_offset INTEGER, byte_start INTEGER DEFAULT -1, byte_end INTEGER DEFAULT -1, ' +
    'PRIMARY KEY (book_id, idx))',
  'CREATE TABLE IF NOT EXISTS bookmarks (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER, char_offset INTEGER, ' +
    'excerpt TEXT, created_at INTEGER)',
  // Upgrade existing installations before applying the uniqueness constraint.
  'DELETE FROM bookmarks WHERE id NOT IN (' +
    'SELECT MIN(id) FROM bookmarks GROUP BY book_id, char_offset)',
  'CREATE UNIQUE INDEX IF NOT EXISTS bookmarks_book_offset ON bookmarks(book_id, char_offset)',
  'CREATE TABLE IF NOT EXISTS reading_days (day TEXT PRIMARY KEY, seconds INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS finished_books (book_id INTEGER PRIMARY KEY, finished_at INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS books_recent ON books(deleted, last_read_at)'
];

export class Db {
  private static store: relationalStore.RdbStore | null = null;
  private static initPromise: Promise<relationalStore.RdbStore> | null = null;
  private static namespace: string = '';

  static init(context: common.UIAbilityContext, namespace: string = ''): Promise<relationalStore.RdbStore> {
    if (namespace !== '' && !/^qa_[a-z0-9_]+$/.test(namespace)) { throw new Error('Invalid database namespace'); }
    if (Db.initPromise !== null) {
      if (namespace !== Db.namespace) { throw new Error('Cannot mix application and QA storage'); }
      return Db.initPromise;
    }
    Db.namespace = namespace;
    const config: relationalStore.StoreConfig = {
      name: namespace === '' ? 'readbooks.db' : namespace + '.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    Db.initPromise = Db.initialize(context, config).catch((error: Error) => {
      Db.initPromise = null;
      throw error;
    });
    return Db.initPromise;
  }

  static booksDirectory(context: common.UIAbilityContext): string {
    return context.filesDir + (Db.namespace === '' ? '/books' : '/' + Db.namespace + '_books');
  }

  private static async initialize(context: common.UIAbilityContext,
    config: relationalStore.StoreConfig): Promise<relationalStore.RdbStore> {
    let store: relationalStore.RdbStore | null = null;
    let transactionStarted: boolean = false;
    try {
      store = await relationalStore.getRdbStore(context, config);
      store.beginTransaction();
      transactionStarted = true;
      for (let i: number = 0; i < DDL.length; i++) {
        store.executeSync(DDL[i]);
      }
      store.commit();
      transactionStarted = false;
      const columns = store.querySqlSync('SELECT * FROM chapters LIMIT 0');
      let hasByteStart: boolean = false;
      let hasByteEnd: boolean = false;
      try {
        hasByteStart = columns.columnNames.indexOf('byte_start') >= 0;
        hasByteEnd = columns.columnNames.indexOf('byte_end') >= 0;
      } finally {
        columns.close();
      }
      const bookColumns = store.querySqlSync('SELECT * FROM books LIMIT 0');
      let hasCoverPath: boolean = false;
      let bookColumnNames: string[] = [];
      try {
        bookColumnNames = bookColumns.columnNames;
        hasCoverPath = bookColumns.columnNames.indexOf('cover_path') >= 0;
      } finally {
        bookColumns.close();
      }
      store.beginTransaction();
      transactionStarted = true;
      if (!hasCoverPath) {
        store.executeSync('ALTER TABLE books ADD COLUMN cover_path TEXT DEFAULT \'\'');
      }
      const bookmarkColumns = store.querySqlSync('SELECT * FROM bookmarks LIMIT 0');
      let hasBookmarkLocator: boolean = false;
      try { hasBookmarkLocator = bookmarkColumns.columnNames.indexOf('epub_location') >= 0; }
      finally { bookmarkColumns.close(); }
      if (!hasBookmarkLocator) { store.executeSync('ALTER TABLE bookmarks ADD COLUMN epub_location TEXT DEFAULT \'\''); }
      ['source_path', 'epub_index', 'epub_location'].forEach((name: string) => {
        if (bookColumnNames.indexOf(name) < 0) {
          store!.executeSync('ALTER TABLE books ADD COLUMN ' + name + ' TEXT DEFAULT \'\'');
        }
      });
      if (!hasByteStart) {
        store.executeSync('ALTER TABLE chapters ADD COLUMN byte_start INTEGER DEFAULT -1');
      }
      if (!hasByteEnd) {
        store.executeSync('ALTER TABLE chapters ADD COLUMN byte_end INTEGER DEFAULT -1');
      }
      store.commit();
      transactionStarted = false;
      Db.store = store;
      return store;
    } catch (e) {
      if (store !== null && transactionStarted) {
        try {
          store.rollBack();
        } catch (rollbackError) {
        }
      }
      if (store !== null) {
        try {
          await store.close();
        } catch (closeError) {
        }
      }
      Db.initPromise = null;
      throw e instanceof Error ? e : new Error('database initialization failed');
    }
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
