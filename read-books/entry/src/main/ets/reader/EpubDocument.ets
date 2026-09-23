import { util, xml } from '@kit.ArkTS';
import { resolveEpubPath, safeEpubPath } from './EpubArchive';

const METADATA_LIMIT: number = 1024 * 1024;
const BLOCKS: Set<string> = new Set<string>(['p', 'div', 'section', 'article', 'blockquote', 'pre', 'li',
  'ul', 'ol', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'tr', 'table', 'figure', 'figcaption', 'hr', 'br']);
const HIDDEN: Set<string> = new Set<string>(['script', 'style', 'head', 'svg', 'math', 'iframe', 'object', 'audio', 'video']);

class EpubXmlNode {
  name: string;
  attributes: Map<string, string> = new Map<string, string>();
  children: EpubXmlNode[] = [];
  text: string = '';

  constructor(name: string) {
    this.name = name;
  }

  attr(name: string): string {
    return this.attributes.get(name) ?? '';
  }

  child(name: string): EpubXmlNode | undefined {
    return this.children.find((node: EpubXmlNode) => node.name === name);
  }

  allText(): string {
    return this.text + this.children.map((node: EpubXmlNode) => node.allText()).join('');
  }
}

export class EpubSpineItem {
  path: string;
  fixed: boolean = false;

  constructor(path: string) {
    this.path = path;
  }
}

export class EpubNavEntry {
  title: string = '';
  path: string = '';
  fragment: string = '';
  depth: number = 0;
}

export class EpubPackage {
  identifier: string = '';
  fonts: Set<string> = new Set<string>();
  mediaTypes: Map<string, string> = new Map<string, string>();
  title: string = '';
  author: string = '';
  spine: EpubSpineItem[] = [];
  navigationPath: string = '';
  coverPath: string = '';
  coverCandidates: string[] = [];
}

export class EpubBody {
  title: string;
  text: string;

  constructor(title: string, text: string) {
    this.title = title;
    this.text = text;
  }
}

function localName(name: string): string {
  return name.substring(name.lastIndexOf(':') + 1).toLowerCase();
}

/** XML never sees a DTD: normal EPUB 2 PUBLIC doctypes are removed, internal subsets rejected. */
function safeXml(source: string): string {
  if (/<!ENTITY\b/i.test(source) || /<!DOCTYPE[^>]*\[/i.test(source)) {
    throw new Error('EPUB 不允许 XML 外部实体或自定义实体');
  }
  let result: string = source.replace(/<!DOCTYPE[^>]*>/gi, '');
  if (/<!DOCTYPE/i.test(result)) {
    throw new Error('EPUB XML 文档类型声明无效');
  }
  // Common XHTML entities normally supplied by an external DTD; resolve only a fixed inert whitelist.
  result = result.replace(/&nbsp;/g, '&#160;').replace(/&mdash;/g, '&#8212;').replace(/&ndash;/g, '&#8211;')
    .replace(/&ldquo;/g, '&#8220;').replace(/&rdquo;/g, '&#8221;').replace(/&lsquo;/g, '&#8216;')
    .replace(/&rsquo;/g, '&#8217;').replace(/&hellip;/g, '&#8230;').replace(/&copy;/g, '&#169;')
    .replace(/&reg;/g, '&#174;').replace(/&bull;/g, '&#8226;').replace(/&shy;/g, '&#173;');
  return result;
}

function textEvent(event: xml.EventType): boolean {
  return event === xml.EventType.TEXT || event === xml.EventType.CDSECT ||
    event === xml.EventType.ENTITY_REFERENCE || event === xml.EventType.WHITESPACE;
}

function parseTree(source: string): EpubXmlNode {
  if (source.length > METADATA_LIMIT) {
    throw new Error('EPUB 元数据超过 1 MiB');
  }
  const tree: EpubXmlNode = new EpubXmlNode('document');
  const stack: EpubXmlNode[] = [tree];
  let count: number = 0;
  let attributeCount: number = 0;
  const bytes: Uint8Array = util.TextEncoder.create('utf-8').encodeInto(safeXml(source));
  const parser: xml.XmlPullParser = new xml.XmlPullParser(bytes.buffer as ArrayBuffer, 'UTF-8');
  parser.parseXml({
    supportDoctype: false,
    ignoreNameSpace: true,
    tokenValueCallbackFunction: (event: xml.EventType, info: xml.ParseInfo): boolean => {
      if (event === xml.EventType.START_TAG) {
        count++;
        if (count > 30000 || stack.length > 64) {
          throw new Error('EPUB XML 层级或节点数量过多');
        }
        const node: EpubXmlNode = new EpubXmlNode(localName(info.getName()));
        stack[stack.length - 1].children.push(node);
        stack.push(node);
      } else if (event === xml.EventType.END_TAG) {
        if (stack.length <= 1 || stack[stack.length - 1].name !== localName(info.getName())) {
          throw new Error('EPUB XML 标签不匹配');
        }
        stack.pop();
      } else if (textEvent(event)) {
        stack[stack.length - 1].text += info.getText();
      }
      return true;
    },
    attributeValueCallbackFunction: (name: string, value: string): boolean => {
      attributeCount++;
      if (attributeCount > 100000 || value.length > 65536) {
        throw new Error('EPUB XML 属性过多或过长');
      }
      const node: EpubXmlNode = stack[stack.length - 1];
      const key: string = localName(name);
      if (key === 'base') {
        throw new Error('暂不支持含 xml:base 的 EPUB');
      }
      node.attributes.set(key, value);
      return true;
    }
  });
  if (stack.length !== 1 || tree.children.length !== 1) {
    throw new Error('EPUB XML 文档不完整');
  }
  return tree.children[0];
}

function cleanTitle(text: string): string {
  return text.replace(/[\u0000-\u001f]/g, ' ').replace(/\s+/g, ' ').trim().substring(0, 200);
}

export class EpubDocument {
  static containerPath(source: string): string {
    const root: EpubXmlNode = parseTree(source);
    const roots: EpubXmlNode | undefined = root.child('rootfiles');
    const opf: EpubXmlNode | undefined = roots?.children.find((node: EpubXmlNode) =>
      node.name === 'rootfile' && node.attr('media-type') === 'application/oebps-package+xml');
    if (root.name !== 'container' || opf === undefined) {
      throw new Error('EPUB 缺少有效的 OPF 入口');
    }
    return safeEpubPath(opf.attr('full-path'));
  }

  static package(source: string, opfPath: string): EpubPackage {
    const root: EpubXmlNode = parseTree(source);
    const metadata: EpubXmlNode | undefined = root.child('metadata');
    const manifest: EpubXmlNode | undefined = root.child('manifest');
    const spine: EpubXmlNode | undefined = root.child('spine');
    if (root.name !== 'package' || !/^[23](\.|$)/.test(root.attr('version')) || metadata === undefined ||
      manifest === undefined || spine === undefined) {
      throw new Error('EPUB OPF 元数据不完整，仅支持 EPUB 2 / 3');
    }
    const result: EpubPackage = new EpubPackage();
    result.identifier = metadata.children.find((node: EpubXmlNode) => node.name === 'identifier' &&
      node.attr('id') === root.attr('unique-identifier'))?.allText() ?? '';
    result.title = cleanTitle(metadata.child('title')?.allText() ?? '');
    result.author = cleanTitle(metadata.children.filter((node: EpubXmlNode) => node.name === 'creator')
      .map((node: EpubXmlNode) => node.allText()).join('、'));
    const fixed: EpubXmlNode | undefined = metadata.children.find((node: EpubXmlNode) =>
      node.name === 'meta' && node.attr('property') === 'rendition:layout' && node.allText().trim() === 'pre-paginated');
    const coverMeta: EpubXmlNode | undefined = metadata.children.find((node: EpubXmlNode) =>
      node.name === 'meta' && node.attr('name') === 'cover');
    const entries: Map<string, EpubXmlNode> = new Map<string, EpubXmlNode>();
    for (let i: number = 0; i < manifest.children.length; i++) {
      const node: EpubXmlNode = manifest.children[i];
      if (node.name !== 'item') {
        continue;
      }
      const id: string = node.attr('id');
      if (id.length === 0 || entries.has(id)) {
        throw new Error('EPUB manifest 存在重复或空 ID');
      }
      entries.set(id, node);
      try {
        const resourcePath = resolveEpubPath(opfPath, node.attr('href'));
        result.mediaTypes.set(resourcePath, node.attr('media-type'));
        if (/font|opentype|truetype/i.test(node.attr('media-type')) || /\.(ttf|otf|woff2?)$/i.test(resourcePath)) {
          result.fonts.add(resourcePath);
        }
      } catch (_) {}
      const properties: string[] = node.attr('properties').split(/\s+/);
      if (properties.indexOf('nav') >= 0) {
        result.navigationPath = resolveEpubPath(opfPath, node.attr('href'));
      }
      if (properties.indexOf('cover-image') >= 0 || id === coverMeta?.attr('content')) {
        // A remote cover is optional and ignored; no network access ever takes place.
        try {
          result.coverPath = resolveEpubPath(opfPath, node.attr('href'));
          EpubDocument.addCoverCandidate(result, opfPath, node.attr('href'));
        } catch (e) {}
      }
    }
    // EPUB 2 often points at an XHTML/SVG wrapper in the guide, not directly at the image.
    root.child('guide')?.children.forEach((node: EpubXmlNode) => {
      if (node.name === 'reference' && node.attr('type').toLowerCase().split(/\s+/).indexOf('cover') >= 0) {
        EpubDocument.addCoverCandidate(result, opfPath, node.attr('href'));
      }
    });
    manifest.children.forEach((node: EpubXmlNode) => {
      if (node.name === 'item' && /(^|[\/_\-. ])(cover|frontcover|front-cover)([\/_\-. ]|$)/i
        .test(node.attr('id') + ' ' + node.attr('href'))) {
        EpubDocument.addCoverCandidate(result, opfPath, node.attr('href'));
      }
    });
    if (result.navigationPath.length === 0 && spine.attr('toc').length > 0) {
      const toc: EpubXmlNode | undefined = entries.get(spine.attr('toc'));
      if (toc !== undefined) {
        result.navigationPath = resolveEpubPath(opfPath, toc.attr('href'));
      }
    }
    for (let i: number = 0; i < spine.children.length; i++) {
      const ref: EpubXmlNode = spine.children[i];
      if (ref.name !== 'itemref' || ref.attr('linear') === 'no') {
        continue;
      }
      const item: EpubXmlNode | undefined = entries.get(ref.attr('idref'));
      if (item === undefined || ['application/xhtml+xml', 'text/html', 'image/svg+xml'].indexOf(item.attr('media-type')) < 0) {
        throw new Error('EPUB 阅读顺序引用了缺失或不支持的正文');
      }
      const spineItem: EpubSpineItem = new EpubSpineItem(resolveEpubPath(opfPath, item.attr('href')));
      spineItem.fixed = fixed !== undefined || item.attr('media-type') === 'image/svg+xml' ||
        ref.attr('properties').split(/\s+/).indexOf('rendition:layout-pre-paginated') >= 0;
      if (ref.attr('properties').split(/\s+/).indexOf('rendition:layout-reflowable') >= 0) { spineItem.fixed = false; }
      result.spine.push(spineItem);
      if (result.spine.length > 10000) {
        throw new Error('EPUB 章节数量超过 10000');
      }
    }
    if (result.spine.length === 0) {
      throw new Error('EPUB 没有阅读顺序');
    }
    // Last fallback: the first reading-order document may contain an unlabelled title-page image.
    if (result.coverCandidates.length < 12 && result.coverCandidates.indexOf(result.spine[0].path) < 0) {
      result.coverCandidates.push(result.spine[0].path);
    }
    return result;
  }

  private static addCoverCandidate(result: EpubPackage, base: string, href: string): void {
    if (result.coverCandidates.length >= 12 || href.length === 0) { return; }
    try {
      const path: string = resolveEpubPath(base, href);
      if (result.coverCandidates.indexOf(path) < 0) { result.coverCandidates.push(path); }
    } catch (e) { /* Optional remote/unsafe covers are never fetched. */ }
  }

  static coverImages(source: string, path: string): string[] {
    const images: string[] = [];
    EpubDocument.collectCoverImages(parseTree(source), path, images);
    return images;
  }

  private static collectCoverImages(node: EpubXmlNode, path: string, images: string[]): void {
    if (images.length >= 4 || ['script', 'style', 'iframe', 'object'].indexOf(node.name) >= 0) { return; }
    const href: string = node.name === 'img' ? node.attr('src') : node.name === 'image' ? node.attr('href') : '';
    if (href.length > 0) {
      try {
        const resolved: string = resolveEpubPath(path, href);
        if (images.indexOf(resolved) < 0) { images.push(resolved); }
      } catch (e) {}
    }
    node.children.forEach((child: EpubXmlNode) => EpubDocument.collectCoverImages(child, path, images));
  }

  static navigation(source: string, path: string): Map<string, string> {
    const root: EpubXmlNode = parseTree(source);
    const titles: Map<string, string> = new Map<string, string>();
    EpubDocument.collectTitles(root, path, titles, root.name === 'ncx');
    return titles;
  }

  /** Keep fragment IDs and nesting; multiple chapters in one XHTML remain distinct links. */
  static navigationEntries(source: string, path: string): EpubNavEntry[] {
    const root = parseTree(source);
    const entries: EpubNavEntry[] = [];
    EpubDocument.collectNavigation(root, path, entries, root.name === 'ncx', 0, root.name === 'ncx');
    return entries;
  }

  /** Only the OCF font-obfuscation algorithm is permitted. This is not DRM decryption. */
  static obfuscatedFonts(source: string): string[] {
    const root = parseTree(source);
    const fonts: string[] = [];
    for (const node of root.children) {
      if (node.name !== 'encrypteddata' || node.child('encryptionmethod')?.attr('algorithm') !== 'http://www.idpf.org/2008/embedding') {
        throw new Error('暂不支持受 DRM 保护或含加密内容的 EPUB');
      }
      const uri = node.child('cipherdata')?.child('cipherreference')?.attr('uri') ?? '';
      if (!uri || uri.includes('#')) { throw new Error('EPUB 字体混淆资源无效'); }
      fonts.push(resolveEpubPath('', uri));
    }
    if (root.name !== 'encryption' || !fonts.length) { throw new Error('EPUB 加密声明无效'); }
    return fonts;
  }

  private static collectNavigation(node: EpubXmlNode, base: string, entries: EpubNavEntry[],
    ncx: boolean, depth: number, inToc: boolean): void {
    const active: boolean = inToc || (node.name === 'nav' &&
      (node.attr('type').split(/\s+/).indexOf('toc') >= 0 || node.attr('role') === 'doc-toc'));
    let href: string = '';
    let title: string = '';
    if (ncx && node.name === 'navpoint') {
      href = node.child('content')?.attr('src') ?? '';
      title = node.child('navlabel')?.allText() ?? '';
    } else if (active && node.name === 'a') { href = node.attr('href'); title = node.allText(); }
    if (href && title.trim() && entries.length < 10000) {
      try {
        const entry = new EpubNavEntry();
        entry.path = resolveEpubPath(base, href);
        const hash: number = href.indexOf('#');
        entry.fragment = hash >= 0 ? href.substring(hash + 1) : '';
        entry.title = cleanTitle(title);
        entry.depth = Math.max(0, depth - 1);
        entries.push(entry);
      } catch (_) { /* External TOC links are not part of offline book navigation. */ }
    }
    node.children.forEach((child: EpubXmlNode) => EpubDocument.collectNavigation(child, base, entries, ncx,
      depth + ((ncx && node.name === 'navpoint') || (!ncx && node.name === 'ol') ? 1 : 0), active));
  }

  private static collectTitles(node: EpubXmlNode, path: string, titles: Map<string, string>, ncx: boolean): void {
    let href: string = '';
    let title: string = '';
    if (ncx && node.name === 'navpoint') {
      href = node.child('content')?.attr('src') ?? '';
      title = node.child('navlabel')?.allText() ?? '';
    } else if (!ncx && node.name === 'a') {
      href = node.attr('href');
      title = node.allText();
    }
    if (href.length > 0 && title.trim().length > 0) {
      const target: string = resolveEpubPath(path, href);
      if (!titles.has(target)) {
        titles.set(target, cleanTitle(title));
      }
    }
    node.children.forEach((child: EpubXmlNode) => EpubDocument.collectTitles(child, path, titles, ncx));
  }

  /** Only text is emitted: scripts/CSS/images/media are neither executed nor fetched. */
  static body(source: string): EpubBody {
    const bytes: Uint8Array = util.TextEncoder.create('utf-8').encodeInto(safeXml(source));
    const parser: xml.XmlPullParser = new xml.XmlPullParser(bytes.buffer as ArrayBuffer, 'UTF-8');
    const stack: string[] = [];
    const pieces: string[] = [];
    let nodes: number = 0;
    let bodyDepth: number = 0;
    let hiddenDepth: number = 0;
    let headingDepth: number = 0;
    let documentTitleDepth: number = 0;
    let heading: string = '';
    let documentTitle: string = '';
    let sawBody: boolean = false;
    parser.parseXml({
      supportDoctype: false,
      ignoreNameSpace: true,
      tokenValueCallbackFunction: (event: xml.EventType, info: xml.ParseInfo): boolean => {
        if (event === xml.EventType.START_TAG) {
          nodes++;
          if (nodes > 200000 || stack.length >= 64) {
            throw new Error('EPUB 正文节点或层级过多');
          }
          const name: string = localName(info.getName());
          stack.push(name);
          if (name === 'body') {
            if (sawBody) {
              throw new Error('EPUB 正文 body 重复');
            }
            bodyDepth = stack.length;
            sawBody = true;
          }
          if (hiddenDepth === 0 && HIDDEN.has(name)) {
            hiddenDepth = stack.length;
          }
          if (name === 'title' && documentTitle.length === 0) {
            documentTitleDepth = stack.length;
          }
          if (bodyDepth > 0 && hiddenDepth === 0) {
            if (BLOCKS.has(name)) {
              pieces.push('\n');
            }
            if (/^h[1-3]$/.test(name) && heading.length === 0 && headingDepth === 0) {
              headingDepth = stack.length;
            }
          }
        } else if (event === xml.EventType.END_TAG) {
          const name: string = localName(info.getName());
          if (stack.length === 0 || stack[stack.length - 1] !== name) {
            throw new Error('EPUB XHTML 标签不匹配');
          }
          if (bodyDepth > 0 && hiddenDepth === 0 && BLOCKS.has(name)) {
            pieces.push('\n');
          }
          if (stack.length === bodyDepth) { bodyDepth = 0; }
          if (stack.length === hiddenDepth) { hiddenDepth = 0; }
          if (stack.length === headingDepth) { headingDepth = 0; }
          if (stack.length === documentTitleDepth) { documentTitleDepth = 0; }
          stack.pop();
        } else if (textEvent(event)) {
          const text: string = info.getText();
          if (documentTitleDepth > 0 && documentTitle.length < 200) {
            documentTitle += text;
          }
          if (bodyDepth > 0 && hiddenDepth === 0) {
            pieces.push(text.replace(/[\t\r\n ]+/g, ' '));
            if (headingDepth > 0 && heading.length < 200) {
              heading += text;
            }
          }
        }
        if (pieces.length > 600000) {
          throw new Error('EPUB 正文碎片过多');
        }
        return true;
      }
    });
    if (!sawBody || stack.length !== 0) {
      throw new Error('EPUB 缺少有效的 XHTML 正文');
    }
    const body: string = pieces.join('').replace(/[ \u00A0]+/g, ' ').replace(/ *\n */g, '\n')
      .replace(/\n{3,}/g, '\n\n').trim();
    return new EpubBody(cleanTitle(heading || documentTitle), body.length > 0 ? body + '\n\n' : '');
  }
}
