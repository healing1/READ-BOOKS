import { relationalStore } from '@kit.ArkData';
import { Db } from './Db';
import { Book } from '../model/Models';

export class BookRepo {
  static async listAll(): Promise<Book[]> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('deleted', 0).orderByDesc('last_read_at');
    const rs = await store.query(predicates);
    const out: Book[] = [];
    while (rs.goToNextRow()) {
      out.push(BookRepo.fromRow(rs));
    }
    rs.close();
    return out;
  }

  static async getById(id: number): Promise<Book | null> {
    const store = await Db.get();
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('id', id);
    const rs = await store.query(predicates);
    let book: Book | null = null;
    if (rs.goToNextRow()) {
      book = BookRepo.fromRow(rs);
    }
    rs.close();
    return book;
  }

  static async insert(book: Book): Promise<number> {
    const store = await Db.get();
    const bucket: relationalStore.ValuesBucket = {
      'title': book.title,
      'author': book.author,
      'format': book.format,
      'size_bytes': book.sizeBytes,
      'encoding': book.encoding,
      'char_count': book.charCount,
      'cover_color': book.coverColor,
      'file_path': book.filePath,
      'created_at': book.createdAt,
      'last_read_at': book.lastReadAt,
      'progress_char_offset': book.progressCharOffset
    };
    return await store.insert('books', bucket);
  }

  static async touchAndSetProgress(id: number, charOffset: number): Promise<void> {
    const store = await Db.get();
    const bucket: relationalStore.ValuesBucket = {
      'progress_char_offset': charOffset,
      'last_read_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('id', id);
    await store.update('books', bucket, predicates);
  }

  static async markDeleted(id: number): Promise<void> {
    const store = await Db.get();
    const bucket: relationalStore.ValuesBucket = {
      'deleted': 1
    };
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('id', id);
    await store.update('books', bucket, predicates);
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
    b.filePath = rs.getString(rs.getColumnIndex('file_path'));
    b.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    b.lastReadAt = rs.getLong(rs.getColumnIndex('last_read_at'));
    b.progressCharOffset = rs.getLong(rs.getColumnIndex('progress_char_offset'));
    return b;
  }
}
