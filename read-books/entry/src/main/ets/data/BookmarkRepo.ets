import { relationalStore } from '@kit.ArkData';
import { Db } from './Db';
import { Bookmark } from '../model/Models';

/** 同一本书的同一字符位置只有一个书签；重复添加返回已有 ID。 */
export class BookmarkRepo {
  static async add(bookId: number, charOffset: number, excerpt: string, epubLocation: string = ''): Promise<number> {
    if (!Number.isSafeInteger(bookId) || bookId <= 0 ||
      !Number.isSafeInteger(charOffset) || charOffset < 0) {
      throw new Error('书签位置无效');
    }
    const store = await Db.get();
    const bookPredicates = new relationalStore.RdbPredicates('books');
    bookPredicates.equalTo('id', bookId).equalTo('deleted', 0);
    const bookRow = store.querySync(bookPredicates, ['char_count']);
    try {
      if (!bookRow.goToFirstRow() || charOffset >= bookRow.getLong(0)) {
        throw new Error('图书已删除或书签位置无效');
      }
    } finally {
      bookRow.close();
    }
    const existingId: number = BookmarkRepo.findId(store, bookId, charOffset);
    if (existingId > 0) {
      return existingId;
    }
    const bucket: relationalStore.ValuesBucket = {
      'book_id': bookId,
      'char_offset': charOffset,
      'excerpt': excerpt.replace(/\s+/g, ' ').trim().substring(0, 160),
      'created_at': Date.now()
    };
    bucket['epub_location'] = epubLocation;
    // No await between the lookup and insert: rapid taps cannot interleave here.
    // The unique index also protects calls from a second database connection.
    try {
      const id: number = store.insertSync('bookmarks', bucket);
      if (id <= 0) {
        throw new Error('添加书签失败');
      }
      return id;
    } catch (e) {
      const duplicateId: number = BookmarkRepo.findId(store, bookId, charOffset);
      if (duplicateId > 0) {
        return duplicateId;
      }
      throw e instanceof Error ? e : new Error('添加书签失败');
    }
  }

  private static findId(store: relationalStore.RdbStore, bookId: number, charOffset: number): number {
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('book_id', bookId).equalTo('char_offset', charOffset);
    const rs = store.querySync(predicates, ['id']);
    try {
      return rs.goToFirstRow() ? rs.getLong(0) : 0;
    } finally {
      rs.close();
    }
  }

  static async listByBook(bookId: number): Promise<Bookmark[]> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('book_id', bookId).orderByDesc('created_at').orderByDesc('id');
    const rs = await store.query(predicates);
    const out: Bookmark[] = [];
    try {
      while (rs.goToNextRow()) {
        const b = new Bookmark();
        b.id = rs.getLong(rs.getColumnIndex('id'));
        b.bookId = bookId;
        b.charOffset = rs.getLong(rs.getColumnIndex('char_offset'));
        b.excerpt = rs.getString(rs.getColumnIndex('excerpt'));
        b.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
        b.epubLocation = rs.getString(rs.getColumnIndex('epub_location'));
        out.push(b);
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async remove(id: number): Promise<void> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('id', id);
    await store.delete(predicates);
  }
}
