import { relationalStore } from '@kit.ArkData';
import { Db } from './Db';
import { Book, Chapter, MAX_CHAPTERS_PER_BOOK } from '../model/Models';

export class BookRepo {
  /** Shared across Reader instances, so an older writer cannot overtake a newer request. */
  private static progressWrites: Map<number, Promise<void>> = new Map<number, Promise<void>>();

  static async listAll(): Promise<Book[]> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('deleted', 0).orderByDesc('last_read_at').orderByDesc('created_at');
    const rs = await store.query(predicates);
    const out: Book[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(BookRepo.fromRow(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async hasAny(): Promise<boolean> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.limitAs(1);
    const rs = await store.query(predicates, ['id']);
    try {
      return rs.goToFirstRow();
    } finally {
      rs.close();
    }
  }

  static async hasLiveFile(path: string): Promise<boolean> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.beginWrap().equalTo('file_path', path).or().equalTo('cover_path', path).or().equalTo('source_path', path)
      .endWrap().equalTo('deleted', 0).limitAs(1);
    const rs = await store.query(predicates, ['id']);
    try {
      return rs.goToFirstRow();
    } finally {
      rs.close();
    }
  }

  static async getById(id: number): Promise<Book | null> {
    const store = await Db.get();
    await BookRepo.drainProgress(id);
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('id', id).equalTo('deleted', 0);
    const rs = await store.query(predicates);
    try {
      if (rs.goToNextRow()) {
        return BookRepo.fromRow(rs);
      }
      return null;
    } finally {
      rs.close();
    }
  }

  static async insert(book: Book): Promise<number> {
    const store = await Db.get();
    const id: number = store.insertSync('books', BookRepo.toValuesBucket(book));
    if (id < 0) {
      throw new Error('insert book failed');
    }
    return id;
  }

  static async insertWithChapters(book: Book, chapters: Chapter[]): Promise<number> {
    if (chapters.length > MAX_CHAPTERS_PER_BOOK) {
      throw new Error('chapters limit exceeded');
    }
    const store = await Db.get();
    let transactionStarted: boolean = false;
    try {
      store.beginTransaction();
      transactionStarted = true;
      const bookId: number = store.insertSync('books', BookRepo.toValuesBucket(book));
      if (bookId < 0) {
        throw new Error('insert book failed');
      }
      for (let i: number = 0; i < chapters.length; i++) {
        const chapter: Chapter = chapters[i];
        const bucket: relationalStore.ValuesBucket = {
          'book_id': bookId,
          'idx': chapter.idx,
          'title': chapter.title,
          'start_offset': chapter.startOffset,
          'end_offset': chapter.endOffset,
          'byte_start': chapter.byteStart,
          'byte_end': chapter.byteEnd
        };
        const chapterId: number = store.insertSync('chapters', bucket);
        if (chapterId < 0) {
          throw new Error('insert chapter failed');
        }
      }
      store.commit();
      transactionStarted = false;
      return bookId;
    } catch (e) {
      if (transactionStarted) {
        try {
          store.rollBack();
        } catch (rollbackError) {
        }
      }
      throw e instanceof Error ? e : new Error('insert book failed');
    }
  }

  static async touchAndSetProgress(id: number, charOffset: number, epubLocation: string = ''): Promise<void> {
    if (!Number.isSafeInteger(id) || id <= 0 || !Number.isSafeInteger(charOffset) || charOffset < 0) {
      throw new Error('阅读位置无效');
    }
    const previous: Promise<void> = BookRepo.progressWrites.get(id) ?? Promise.resolve();
    // A failed write is still reported to its caller, but must not poison later saves.
    const write: Promise<void> = previous.catch(() => {}).then(() => BookRepo.writeProgress(id, charOffset, epubLocation));
    BookRepo.progressWrites.set(id, write);
    try {
      await write;
    } finally {
      if (BookRepo.progressWrites.get(id) === write) {
        BookRepo.progressWrites.delete(id);
      }
    }
  }

  private static async drainProgress(id: number): Promise<void> {
    let pending: Promise<void> | undefined = BookRepo.progressWrites.get(id);
    while (pending !== undefined) {
      try {
        await pending;
      } catch (e) {
        // Read the last persisted position if storage rejected a save; its caller reports the failure.
      }
      // Let a Reader's coalescing loop enqueue its next saved anchor before testing for an empty queue.
      await Promise.resolve();
      const next: Promise<void> | undefined = BookRepo.progressWrites.get(id);
      if (next === pending) {
        return;
      }
      pending = next;
    }
  }

  private static async writeProgress(id: number, charOffset: number, epubLocation: string): Promise<void> {
    const store = await Db.get();
    const bucket: relationalStore.ValuesBucket = {
      'progress_char_offset': charOffset,
      'last_read_at': Date.now()
    };
    if (epubLocation.length > 0) { bucket['epub_location'] = epubLocation; }
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('id', id).equalTo('deleted', 0);
    await store.update(bucket, predicates);
  }

  static async markDeleted(id: number): Promise<string> {
    const store = await Db.get();
    store.beginTransaction();
    try {
      const predicates = new relationalStore.RdbPredicates('books');
      predicates.equalTo('id', id);
      const rs = store.querySync(predicates, ['cover_path']);
      let coverPath: string = '';
      try { if (rs.goToFirstRow()) { coverPath = rs.getString(rs.getColumnIndex('cover_path')); } }
      finally { rs.close(); }
      // Retain the tombstone so outstanding progress writes cannot resurrect a deleted book.
      store.executeSync('UPDATE books SET deleted = 1 WHERE id = ?', [id]);
      store.executeSync('DELETE FROM chapters WHERE book_id = ?', [id]);
      store.executeSync('DELETE FROM bookmarks WHERE book_id = ?', [id]);
      store.executeSync('DELETE FROM finished_books WHERE book_id = ?', [id]);
      store.commit();
      return coverPath;
    } catch (e) {
      store.rollBack();
      throw e instanceof Error ? e : new Error('删除图书失败');
    }
  }

  /** Attach the original edition without replacing the legacy text, progress or bookmarks. */
  static async attachEpub(id: number, sourcePath: string, index: string): Promise<void> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('id', id).equalTo('deleted', 0).equalTo('source_path', '');
    const count = await store.update({ 'source_path': sourcePath, 'epub_index': index }, predicates);
    if (count !== 1) { throw new Error('图书已被删除或已补全原版，请重新打开'); }
  }

  /** Compare-and-swap prevents background repair from overwriting a user's newer cover or resurrecting a deletion. */
  static async replaceCover(id: number, path: string, expectedPath: string): Promise<string> {
    const store = await Db.get();
    store.beginTransaction();
    try {
      const predicates = new relationalStore.RdbPredicates('books');
      predicates.equalTo('id', id).equalTo('deleted', 0);
      const rs = store.querySync(predicates, ['cover_path']);
      let previous: string = '';
      try {
        if (!rs.goToFirstRow()) { throw new Error('图书已被删除，封面未修改'); }
        previous = rs.getString(rs.getColumnIndex('cover_path'));
      } finally { rs.close(); }
      if (previous !== expectedPath) { throw new Error('封面已更新，请重新打开图书选项'); }
      store.updateSync({ 'cover_path': path }, predicates);
      store.commit();
      return previous;
    } catch (e) {
      store.rollBack();
      throw e instanceof Error ? e : new Error('保存封面失败');
    }
  }

  static async removeById(id: number): Promise<void> {
    const store = await Db.get();
    store.beginTransaction();
    try {
      store.executeSync('DELETE FROM chapters WHERE book_id = ?', [id]);
      store.executeSync('DELETE FROM bookmarks WHERE book_id = ?', [id]);
      store.executeSync('DELETE FROM finished_books WHERE book_id = ?', [id]);
      store.executeSync('DELETE FROM books WHERE id = ?', [id]);
      store.commit();
    } catch (e) {
      store.rollBack();
      throw e instanceof Error ? e : new Error('清理图书失败');
    }
  }

  private static toValuesBucket(book: Book): relationalStore.ValuesBucket {
    return {
      'title': book.title,
      'author': book.author,
      'format': book.format,
      'size_bytes': book.sizeBytes,
      'encoding': book.encoding,
      'char_count': book.charCount,
      'cover_color': book.coverColor,
      'cover_path': book.coverPath,
      'file_path': book.filePath,
      'source_path': book.sourcePath,
      'epub_index': book.epubIndex,
      'epub_location': book.epubLocation,
      'created_at': book.createdAt,
      'last_read_at': book.lastReadAt,
      'progress_char_offset': book.progressCharOffset
    };
  }

  private static fromRow(rs: relationalStore.ResultSet): Book {
    const b = new Book();
    b.id = rs.getLong(rs.getColumnIndex('id'));
    b.title = rs.getString(rs.getColumnIndex('title'));
    b.author = rs.getString(rs.getColumnIndex('author'));
    b.format = rs.getString(rs.getColumnIndex('format'));
    b.sizeBytes = rs.getLong(rs.getColumnIndex('size_bytes'));
    b.encoding = rs.getString(rs.getColumnIndex('encoding'));
    b.charCount = rs.getLong(rs.getColumnIndex('char_count'));
    b.coverColor = rs.getString(rs.getColumnIndex('cover_color'));
    b.coverPath = rs.getString(rs.getColumnIndex('cover_path'));
    b.filePath = rs.getString(rs.getColumnIndex('file_path'));
    b.sourcePath = rs.getString(rs.getColumnIndex('source_path'));
    b.epubIndex = rs.getString(rs.getColumnIndex('epub_index'));
    b.epubLocation = rs.getString(rs.getColumnIndex('epub_location'));
    b.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    b.lastReadAt = rs.getLong(rs.getColumnIndex('last_read_at'));
    b.progressCharOffset = rs.getLong(rs.getColumnIndex('progress_char_offset'));
    return b;
  }
}
