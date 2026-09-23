import { ReadingSettings } from '../model/ReadingSettings';

/** Built-in faces are original, licensed binaries. Custom selections remain separately stored. */
export class ReadingFonts {
  static choice(settings: ReadingSettings): string {
    if (['default', 'song', 'kai', 'custom'].indexOf(settings.fontChoice) >= 0) {
      return settings.fontChoice === 'custom' && !settings.fontPath ? 'default' : settings.fontChoice;
    }
    return settings.fontPath ? 'custom' : 'default';
  }

  static family(settings: ReadingSettings): string {
    const choice: string = ReadingFonts.choice(settings);
    if (choice === 'song') { return 'ReadBooksSong'; }
    if (choice === 'kai') { return 'ReadBooksKai'; }
    return choice === 'custom' && settings.fontFamily ? settings.fontFamily : 'sans-serif';
  }

  static request(settings: ReadingSettings): string {
    const choice: string = ReadingFonts.choice(settings);
    if (choice === 'song') { return '__reader_song__.otf'; }
    if (choice === 'kai') { return '__reader_kai__.ttf'; }
    return choice === 'custom' ? '__reader_font__?v=' + encodeURIComponent(settings.fontFamily) : '';
  }

  static resource(request: string): string {
    if (request === '__reader_song__.otf') { return 'fonts/SourceHanSerifSC-Regular.otf'; }
    if (request === '__reader_kai__.ttf') { return 'fonts/LXGWWenKai-Regular.ttf'; }
    return '';
  }
}
