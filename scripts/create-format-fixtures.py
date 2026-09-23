"""Generate small, deterministic, wholly local PDF/EPUB integration fixtures."""
from pathlib import Path
from io import BytesIO
import json
import zipfile
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor
from pypdf import PdfReader, PdfWriter
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tmp' / 'pdfs'
OUT.mkdir(parents=True, exist_ok=True)
RES = ROOT / 'read-books' / 'entry' / 'src' / 'ohosTest' / 'resources' / 'rawfile' / 'formats'
RES.mkdir(parents=True, exist_ok=True)
pdfmetrics.registerFont(TTFont('FixtureChinese', 'C:/Windows/Fonts/simhei.ttf'))
buffer = BytesIO()
c = canvas.Canvas(buffer, pagesize=(500, 700), invariant=1)
c.setTitle('格式验证 · 五页图书')
c.setAuthor('READ BOOKS QA')
for page in range(1, 6):
    c.setFillColor(HexColor('#FAF7F0'))
    c.rect(0, 0, 500, 700, stroke=0, fill=1)
    c.setFillColor(HexColor('#235C83'))
    c.setFont('FixtureChinese', 13)
    c.drawString(42, 644, 'READ BOOKS / PDF')
    c.setFillColor(HexColor('#1C1C1E'))
    c.setFont('FixtureChinese', 30)
    c.drawString(42, 586, '格式验证')
    c.setFont('FixtureChinese', 19)
    c.drawString(42, 550, f'第 {page} 页，共 5 页')
    c.setFont('FixtureChinese', 13)
    for y, line in enumerate(['这是一份真实 PDF 测试文档。', '中文、英文、矢量图形和页面边界应保持清晰。',
                              'Page layout remains fixed when zooming.', '单页与双页切换后，当前位置应保持。']):
        c.drawString(42, 492 - y * 28, line)
    for i, color in enumerate(['#235C83', '#446C59', '#913B45']):
        c.setFillColor(HexColor(color))
        c.roundRect(42 + i * 139, 224, 124, 116, 10, stroke=0, fill=1)
        c.setFillColor(HexColor('#FFFFFF'))
        c.setFont('FixtureChinese', 24)
        c.drawCentredString(104 + i * 139, 272, str(page * 10 + i))
    c.setFillColor(HexColor('#6E6E73'))
    c.setFont('FixtureChinese', 12)
    c.drawCentredString(250, 42, f'{page} / 5')
    c.showPage()
c.save()
pdf = buffer.getvalue()
(OUT / 'reading-fixture.pdf').write_bytes(pdf)
(RES / 'reading-fixture.pdf').write_bytes(pdf)
encrypted = PdfWriter(clone_from=PdfReader(BytesIO(pdf)))
encrypted.encrypt('fixture-password')
with (RES / 'encrypted-fixture.pdf').open('wb') as target:
    encrypted.write(target)
(RES / 'invalid-fixture.pdf').write_bytes(b'%PDF-1.7\ninvalid object graph\n%%EOF')

container = '''<?xml version="1.0" encoding="UTF-8"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'''
opf = '''<?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">urn:readbooks:fixture</dc:identifier><dc:title>格式验证 EPUB</dc:title><dc:creator>阅读测试作者</dc:creator><dc:language>zh-CN</dc:language><meta property="dcterms:modified">2026-09-08T00:00:00Z</meta></metadata><manifest><item id="second" href="second.xhtml" media-type="application/xhtml+xml"/><item id="first" href="first.xhtml" media-type="application/xhtml+xml"/><item id="last" href="last.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest><spine><itemref idref="first"/><itemref idref="second"/><itemref idref="last"/></spine></package>'''
chapters = [('first.xhtml', '山间来信', '这是阅读顺序的第一章。中文与 English words 应按原文排列。'),
            ('second.xhtml', '海边的下午', '第二章内容。实体 &amp; &lt; &gt; 和 emoji 😀 都不能损坏。'),
            ('last.xhtml', '最后一页', '第三章结尾。书签与字符偏移可以在重排后恢复。')]

cover_buffer = BytesIO()
cover_image = Image.new('RGB', (320, 460), '#235C83')
cover_draw = ImageDraw.Draw(cover_image)
cover_draw.rectangle((30, 30, 290, 430), outline='#E9D5A1', width=3)
cover_draw.text((80, 200), 'EPUB / READING', fill='#FFFFFF')
cover_image.save(cover_buffer, format='PNG')
(RES / 'cover-fixture.png').write_bytes(cover_buffer.getvalue())

def epub_bytes(version='3.0', extra=None, cover_mode='metadata'):
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, 'w') as z:
        z.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        z.writestr('META-INF/container.xml', container, compress_type=zipfile.ZIP_DEFLATED)
        package = opf.replace('version="3.0"', f'version="{version}"')
        package = package.replace('</metadata>', '<meta name="cover" content="cover"/></metadata>')
        package = package.replace('<manifest>', '<manifest><item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>')
        if version == '2.0':
            package = package.replace('<spine>', '<spine toc="ncx">')
            package = package.replace('<manifest>', '<manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>')
            package = package.replace('<meta property="dcterms:modified">2026-09-08T00:00:00Z</meta>', '')
            package = package.replace(' properties="cover-image"', '').replace(' properties="nav"', '')
            ncx = '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="urn:readbooks:fixture"/></head><docTitle><text>格式验证 EPUB</text></docTitle><navMap>'
            for i, (filename, title, _) in enumerate(chapters, 1):
                ncx += f'<navPoint id="n{i}" playOrder="{i}"><navLabel><text>{title}</text></navLabel><content src="{filename}"/></navPoint>'
            ncx += '</navMap></ncx>'
            z.writestr('OPS/toc.ncx', ncx, compress_type=zipfile.ZIP_DEFLATED)
        if cover_mode != 'metadata':
            package = package.replace('<meta name="cover" content="cover"/>', '').replace(' properties="cover-image"', '')
        if cover_mode in ('guide', 'svg-wrapper'):
            package = package.replace('id="cover" href="cover.png"', 'id="artwork" href="artwork.png"')
            package = package.replace('</manifest>', '<item id="title-page" href="text/title.xhtml" media-type="application/xhtml+xml"/></manifest>')
            package = package.replace('</package>', '<guide><reference type="cover" href="text/title.xhtml"/></guide></package>')
            wrapper = '<img src="../artwork.png"/>' if cover_mode == 'guide' else '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="../artwork.png"/></svg>'
            z.writestr('OPS/text/title.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><body>' + wrapper + '</body></html>', compress_type=zipfile.ZIP_DEFLATED)
            z.writestr('OPS/artwork.png', cover_buffer.getvalue(), compress_type=zipfile.ZIP_DEFLATED)
        z.writestr('OPS/package.opf', package, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr('OPS/cover.png', cover_buffer.getvalue(), compress_type=zipfile.ZIP_DEFLATED)
        for filename, title, content in chapters:
            body = f'<html xmlns="http://www.w3.org/1999/xhtml"><head><title>{title}</title><style>body{{color:black}}</style></head><body><h1>{title}</h1>' + (f'<p>{content}</p>' * 5) + '</body></html>'
            z.writestr('OPS/' + filename, body, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr('OPS/nav.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><body><nav><ol><li><a href="first.xhtml">山间来信</a></li></ol></nav></body></html>', compress_type=zipfile.ZIP_DEFLATED)
        if extra:
            z.writestr(extra[0], extra[1])
    return buffer.getvalue()

for name, version, extra in [
    ('reading-fixture.epub', '3.0', None), ('epub2-fixture.epub', '2.0', None),
    ('unsafe-fixture.epub', '3.0', ('../escape.txt', 'must not be extracted')),
    ('encrypted-fixture.epub', '3.0', ('META-INF/encryption.xml', '<encryption><EncryptedData/></encryption>'))]:
    (RES / name).write_bytes(epub_bytes(version, extra))
for mode in ('guide', 'svg-wrapper', 'filename'):
    (RES / f'cover-{mode}.epub').write_bytes(epub_bytes('2.0', cover_mode=mode))
(RES / 'invalid-fixture.epub').write_bytes(b'PK\x03\x04truncated ZIP')
manifest = {p.name: p.stat().st_size for p in RES.iterdir() if p.is_file()}
print(json.dumps(manifest, ensure_ascii=False, indent=2))
