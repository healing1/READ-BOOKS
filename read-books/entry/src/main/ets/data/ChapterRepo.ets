import { relationalStore } from '@kit.ArkData';
import { Db } from './Db';
import { Chapter } from '../model/Models';

export class ChapterRepo {
  static async insertAll(bookId: number, chapters: Chapter[]): Promise<void> {
    if (chapters.length === 0) {
      return;
    }
    const store = await Db.get();
    let transactionStarted: boolean = false;
    try {
      store.beginTransaction();
      transactionStarted = true;
      const book = store.querySqlSync('SELECT id FROM books WHERE id = ? AND deleted = 0', [bookId]);
      let exists: boolean = false;
      try {
        exists = book.goToFirstRow();
      } finally {
        book.close();
      }
      if (!exists) {
        throw new Error('图书已删除，不能建立章节索引');
      }
      for (let i = 0; i < chapters.length; i++) {
        const c = chapters[i];
        const bucket: relationalStore.ValuesBucket = {
          'book_id': bookId,
          'idx': c.idx,
          'title': c.title,
          'start_offset': c.startOffset,
          'end_offset': c.endOffset,
          'byte_start': c.byteStart,
          'byte_end': c.byteEnd
        };
        const id: number = store.insertSync('chapters', bucket);
        if (id < 0) {
          throw new Error('insert chapter failed');
        }
      }
      store.commit();
      transactionStarted = false;
    } catch (e) {
      if (transactionStarted) {
        try {
          store.rollBack();
        } catch (rollbackError) {
        }
      }
      throw e instanceof Error ? e : new Error('insert chapters failed');
    }
  }

  static async listByBook(bookId: number): Promise<Chapter[]> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('chapters');
    predicates.equalTo('book_id', bookId).orderByAsc('idx');
    const rs = await store.query(predicates);
    const out: Chapter[] = [];
    try {
      while (rs.goToNextRow()) {
        const c = new Chapter();
        c.bookId = bookId;
        c.idx = rs.getLong(rs.getColumnIndex('idx'));
        c.title = rs.getString(rs.getColumnIndex('title'));
        c.startOffset = rs.getLong(rs.getColumnIndex('start_offset'));
        c.endOffset = rs.getLong(rs.getColumnIndex('end_offset'));
        c.byteStart = rs.getLong(rs.getColumnIndex('byte_start'));
        c.byteEnd = rs.getLong(rs.getColumnIndex('byte_end'));
        out.push(c);
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async updateByteIndex(bookId: number, chapters: Chapter[]): Promise<void> {
    const store = await Db.get();
    store.beginTransaction();
    try {
      for (let i: number = 0; i < chapters.length; i++) {
        const chapter: Chapter = chapters[i];
        store.executeSync('UPDATE chapters SET byte_start = ?, byte_end = ? WHERE book_id = ? AND idx = ?',
          [chapter.byteStart, chapter.byteEnd, bookId, chapter.idx]);
      }
      store.commit();
    } catch (e) {
      store.rollBack();
      throw e instanceof Error ? e : new Error('建立章节索引失败');
    }
  }
}
