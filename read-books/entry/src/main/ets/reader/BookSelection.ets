import { Book } from '../model/Models';

/** Opening the first page counts as reading; importing alone does not. */
export class BookSelection {
  static candidates(books: Book[]): Book[] {
    const personal = books.filter((book: Book) => book.title !== '示例 · 西游记（节选）');
    return personal.length > 0 ? personal : books;
  }

  static recent(books: Book[], finished: number[]): Book[] {
    return BookSelection.candidates(books).filter((book: Book) => book.lastReadAt > 0 && finished.indexOf(book.id) < 0)
      .sort((a: Book, b: Book) => b.lastReadAt - a.lastReadAt || b.id - a.id);
  }

  static featured(books: Book[], finished: number[]): Book {
    return BookSelection.recent(books, finished)[0] ??
      BookSelection.candidates(books).slice().sort((a: Book, b: Book) => b.createdAt - a.createdAt || b.id - a.id)[0] ?? new Book();
  }

  static suggestions(books: Book[], featuredId: number): Book[] {
    return books.filter((book: Book) => book.id !== featuredId)
      .sort((a: Book, b: Book) => b.createdAt - a.createdAt || b.id - a.id).slice(0, 10);
  }
}
