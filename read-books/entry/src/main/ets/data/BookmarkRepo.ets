import { relationalStore } from '@kit.ArkData';
import { Db } from './Db';
import { Bookmark } from '../model/Models';

/** 书签仓储 —— 表结构就绪，UI 待 M4 */
export class BookmarkRepo {
  static async add(bookId: number, charOffset: number, excerpt: string): Promise<number> {
    const store = await Db.get();
    const bucket: relationalStore.ValuesBucket = {
      'book_id': bookId,
      'char_offset': charOffset,
      'excerpt': excerpt,
      'created_at': Date.now()
    };
    return await store.insert('bookmarks', bucket);
  }

  static async listByBook(bookId: number): Promise<Bookmark[]> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('book_id', bookId).orderByDesc('created_at');
    const rs = await store.query(predicates);
    const out: Bookmark[] = [];
    while (rs.goToNextRow()) {
      const b = new Bookmark();
      b.id = rs.getLong(rs.getColumnIndex('id'));
      b.bookId = bookId;
      b.charOffset = rs.getLong(rs.getColumnIndex('char_offset'));
      b.excerpt = rs.getString(rs.getColumnIndex('excerpt'));
      b.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
      out.push(b);
    }
    rs.close();
    return out;
  }

  static async remove(id: number): Promise<void> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('id', id);
    await store.delete(predicates);
  }
}
