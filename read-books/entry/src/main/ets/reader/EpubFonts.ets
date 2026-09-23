import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { EpubArchive } from './EpubArchive';
import { EpubDocument, EpubPackage } from './EpubDocument';

/** W3C OCF font obfuscation: https://www.w3.org/publishing/epub32/epub-ocf.html#sec-resource-obfuscation */
export class EpubFonts {
  private paths: Set<string> = new Set<string>();
  private key: Uint8Array = new Uint8Array();
  static async inspect(archive: EpubArchive, metadata: EpubPackage): Promise<EpubFonts> {
    const fonts = new EpubFonts();
    if (!archive.has('META-INF/encryption.xml')) { return fonts; }
    const paths = EpubDocument.obfuscatedFonts(await archive.readText('META-INF/encryption.xml', 1024 * 1024));
    for (const path of paths) {
      if (!metadata.fonts.has(path) || !archive.has(path)) { throw new Error('只支持字体混淆，不支持加密正文'); }
      fonts.paths.add(path);
    }
    const identifier = metadata.identifier.replace(/[ \t\r\n]/g, '');
    if (!identifier) { throw new Error('混淆字体缺少出版物唯一标识'); }
    const hash = cryptoFramework.createMd('SHA1');
    await hash.update({ data: util.TextEncoder.create('utf-8').encodeInto(identifier) });
    fonts.key = (await hash.digest()).data;
    return fonts;
  }
  decode(path: string, data: Uint8Array): Uint8Array {
    if (!this.paths.has(path)) { return data; }
    const output = data.slice();
    for (let i: number = 0; i < Math.min(1040, output.length); i++) { output[i] ^= this.key[i % this.key.length]; }
    return output;
  }
}
