import { relationalStore } from '@kit.ArkData';
import { Db } from './Db';

export class ReadingDay {
  date: string = '';
  seconds: number = 0;
}

export class ReadingSummary {
  todaySeconds: number = 0;
  totalSeconds: number = 0;
  readingDays: number = 0;
  streak: number = 0;
  bestStreak: number = 0;
  week: ReadingDay[] = [];
  finishedIds: number[] = [];
  yearFinishedIds: number[] = [];
}

export class ReadingActivityRepo {
  private static pending: Promise<void> = Promise.resolve();
  private static initialized: boolean = false;

  static dateKey(date: Date): string {
    return date.getFullYear() + '-' + (date.getMonth() + 1).toString().padStart(2, '0') + '-' +
      date.getDate().toString().padStart(2, '0');
  }

  private static async store(): Promise<relationalStore.RdbStore> {
    const store = await Db.get();
    if (!ReadingActivityRepo.initialized) {
      store.executeSync('CREATE TABLE IF NOT EXISTS reading_days (day TEXT PRIMARY KEY, seconds INTEGER NOT NULL)');
      store.executeSync('CREATE TABLE IF NOT EXISTS finished_books (book_id INTEGER PRIMARY KEY, finished_at INTEGER NOT NULL)');
      ReadingActivityRepo.initialized = true;
    }
    return store;
  }

  static async recordInterval(start: number, end: number): Promise<void> {
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
      return;
    }
    const task = ReadingActivityRepo.pending.catch(() => {}).then(async () => {
      const store = await ReadingActivityRepo.store();
      let cursor: number = start;
      while (cursor < end) {
        const date = new Date(cursor);
        const midnight = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime();
        const stop: number = Math.min(end, midnight);
        const seconds: number = Math.floor((stop - cursor) / 1000);
        if (seconds > 0) {
          const day: string = ReadingActivityRepo.dateKey(date);
          store.executeSync('INSERT OR IGNORE INTO reading_days (day, seconds) VALUES (?, 0)', [day]);
          store.executeSync('UPDATE reading_days SET seconds = seconds + ? WHERE day = ?', [seconds, day]);
        }
        cursor = stop;
      }
    });
    ReadingActivityRepo.pending = task;
    await task;
  }

  static async setFinished(bookId: number, finished: boolean): Promise<void> {
    const store = await ReadingActivityRepo.store();
    if (finished) {
      store.executeSync('INSERT OR IGNORE INTO finished_books (book_id, finished_at) VALUES (?, ?)', [bookId, Date.now()]);
    } else {
      store.executeSync('DELETE FROM finished_books WHERE book_id = ?', [bookId]);
    }
  }

  static async summary(goalMinutes: number): Promise<ReadingSummary> {
    await ReadingActivityRepo.pending.catch(() => {});
    const store = await ReadingActivityRepo.store();
    const result = new ReadingSummary();
    const days: Map<string, number> = new Map<string, number>();
    const rows = await store.query(new relationalStore.RdbPredicates('reading_days').orderByAsc('day'));
    try {
      while (rows.goToNextRow()) {
        const key: string = rows.getString(0);
        const seconds: number = rows.getLong(1);
        days.set(key, seconds);
        result.totalSeconds += seconds;
        if (seconds > 0) {
          result.readingDays++;
        }
      }
    } finally {
      rows.close();
    }
    const now = new Date();
    const today: string = ReadingActivityRepo.dateKey(now);
    result.todaySeconds = days.get(today) ?? 0;
    const goal: number = goalMinutes * 60;
    let cursor = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    if (result.todaySeconds < goal) {
      cursor.setDate(cursor.getDate() - 1);
    }
    while ((days.get(ReadingActivityRepo.dateKey(cursor)) ?? 0) >= goal) {
      result.streak++;
      cursor.setDate(cursor.getDate() - 1);
    }
    let streak: number = 0;
    let previous: string = '';
    days.forEach((seconds: number, key: string) => {
      const parts: string[] = key.split('-');
      const date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
      date.setDate(date.getDate() - 1);
      streak = seconds >= goal ? (ReadingActivityRepo.dateKey(date) === previous ? streak + 1 : 1) : 0;
      result.bestStreak = Math.max(result.bestStreak, streak);
      previous = key;
    });
    for (let i: number = 0; i < 7; i++) {
      const date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay() + i);
      const day = new ReadingDay();
      day.date = ReadingActivityRepo.dateKey(date);
      day.seconds = days.get(day.date) ?? 0;
      result.week.push(day);
    }
    const finished = await store.querySql('SELECT f.book_id, f.finished_at FROM finished_books f ' +
      'INNER JOIN books b ON b.id = f.book_id WHERE b.deleted = 0 ORDER BY f.finished_at DESC');
    try {
      while (finished.goToNextRow()) {
        const id: number = finished.getLong(0);
        result.finishedIds.push(id);
        if (new Date(finished.getLong(1)).getFullYear() === now.getFullYear()) {
          result.yearFinishedIds.push(id);
        }
      }
    } finally {
      finished.close();
    }
    return result;
  }
}
