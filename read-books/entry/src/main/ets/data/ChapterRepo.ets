import { relationalStore } from '@kit.ArkData';
import { Db } from './Db';
import { Chapter } from '../model/Models';

export class ChapterRepo {
  static async insertAll(bookId: number, chapters: Chapter[]): Promise<void> {
    if (chapters.length === 0) {
      return;
    }
    const store = await Db.get();
    store.beginTransaction();
    try {
      for (let i = 0; i < chapters.length; i++) {
        const c = chapters[i];
        const bucket: relationalStore.ValuesBucket = {
          'book_id': bookId,
          'idx': c.idx,
          'title': c.title,
          'start_offset': c.startOffset,
          'end_offset': c.endOffset
        };
        await store.insert('chapters', bucket);
      }
      store.commit();
    } catch (e) {
      store.rollBack();
      throw e instanceof Error ? e : new Error('insert chapters failed');
    }
  }

  static async listByBook(bookId: number): Promise<Chapter[]> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('chapters');
    predicates.equalTo('book_id', bookId).orderByAsc('idx');
    const rs = await store.query(predicates);
    const out: Chapter[] = [];
    while (rs.goToNextRow()) {
      const c = new Chapter();
      c.bookId = bookId;
      c.idx = rs.getLong(rs.getColumnIndex('idx'));
      c.title = rs.getString(rs.getColumnIndex('title'));
      c.startOffset = rs.getLong(rs.getColumnIndex('start_offset'));
      c.endOffset = rs.getLong(rs.getColumnIndex('end_offset'));
      out.push(c);
    }
    rs.close();
    return out;
  }
}
