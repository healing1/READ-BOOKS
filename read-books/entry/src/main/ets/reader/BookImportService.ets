import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { Book } from '../model/Models';
import { ImportService } from './ImportService';
import { EpubImporter } from './EpubImporter';
import { PdfImporter } from './PdfImporter';

/** One import entry point; formats keep separate parsers and storage semantics. */
export class BookImportService {
  static async importFromUri(context: common.UIAbilityContext, uri: string): Promise<Book> {
    let name: string = uri.substring(uri.lastIndexOf('/') + 1).split('?')[0];
    try { name = decodeURIComponent(name); } catch (e) {}
    name = name.toLowerCase();
    if (name.endsWith('.epub')) {
      return EpubImporter.importFromUri(context, uri);
    }
    if (name.endsWith('.pdf')) {
      return PdfImporter.importFromUri(context, uri);
    }
    if (name.endsWith('.txt')) {
      return ImportService.importFromUri(context, uri);
    }
    // Some system providers return opaque URIs. Inspect only the signature; parsers do full validation.
    const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    const header: Uint8Array = new Uint8Array(8);
    let length: number = 0;
    try {
      length = await fs.read(file.fd, header.buffer, { length: header.length });
    } finally {
      await fs.close(file);
    }
    if (length >= 5 && header[0] === 37 && header[1] === 80 && header[2] === 68 && header[3] === 70 && header[4] === 45) {
      return PdfImporter.importFromUri(context, uri);
    }
    if (length >= 4 && header[0] === 80 && header[1] === 75 && header[2] === 3 && header[3] === 4) {
      return EpubImporter.importFromUri(context, uri);
    }
    throw new Error('请选择 TXT、EPUB 或 PDF 图书文件');
  }
}
