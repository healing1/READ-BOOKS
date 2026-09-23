"""Locally authored EPUB fixtures: image/CSS/links/fonts/fixed layout; no external content."""
from pathlib import Path
from io import BytesIO
import zipfile
import hashlib
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tmp' / 'epub-visual'
OUT.mkdir(parents=True, exist_ok=True)
RES = ROOT / 'read-books/entry/src/ohosTest/resources/rawfile/formats'
art = Image.new('RGB', (1200, 600), '#225D78')
draw = ImageDraw.Draw(art)
draw.ellipse((740, 60, 1000, 320), fill='#E7CB96')
draw.polygon([(0, 560), (300, 240), (580, 530), (870, 300), (1200, 550), (1200, 600), (0, 600)], fill='#6E9B91')
buf = BytesIO()
art.save(buf, format='PNG')
art_bytes = buf.getvalue()
(OUT / 'reading-background.png').write_bytes(art_bytes)
font = (ROOT / 'read-books/entry/src/main/resources/rawfile/fonts/DMSans.ttf').read_bytes()
(OUT / 'Reading-QA.ttf').write_bytes(font)
(RES / 'reading-background.png').write_bytes(art_bytes)
(RES / 'Reading-QA.ttf').write_bytes(font)
container = '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'
def page(body, title='图文阅读验证', head=''):
    return '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>'+title+'</title><link rel="stylesheet" href="style.css"/>'+head+'</head><body>'+body+'</body></html>'

for fixed in (False, True):
    name = 'qa-fixed.epub' if fixed else 'qa-illustrated.epub'
    title = '原版绘本 · QA' if fixed else '山海图文 · QA'
    metadata = '<meta property="rendition:layout">pre-paginated</meta>' if fixed else ''
    package = '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">urn:qa:visual</dc:identifier><dc:title>'+title+'</dc:title><dc:creator>READ BOOKS QA</dc:creator>'+metadata+'</metadata><manifest>'
    for ident, href, mime, prop in [('first','first.xhtml','application/xhtml+xml',''), ('second','second.xhtml','application/xhtml+xml',''), ('image','image.xhtml','application/xhtml+xml',''), ('nav','nav.xhtml','application/xhtml+xml','nav'), ('css','style.css','text/css',''), ('art','art.png','image/png','cover-image'), ('font','book.ttf','font/ttf','')]:
        package += f'<item id="{ident}" href="{href}" media-type="{mime}" properties="{prop}"/>'
    package += '</manifest><spine><itemref idref="first"/><itemref idref="second"/><itemref idref="image"/></spine></package>'
    links = '<nav epub:type="toc"><h1>目录</h1><ol><li><a href="first.xhtml#picture">山海插图</a></li><li><a href="second.xhtml#chapter">海边来信</a><ol><li><a href="second.xhtml#detail">深入阅读</a></li></ol></li><li><a href="image.xhtml">纯图片页</a></li></ol></nav>'
    paragraph = '沿着山与海的边界行走，读者应当能看到清晰的图文，而不是只有提取后的文字。Images, tables and publisher typography stay together. '
    first = page(links+'<h1 id="picture">山海插图</h1><figure><img src="art.png" alt="蓝色山海与暖黄色月亮"/><figcaption>图 1 · 本地 PNG，宽高比 2:1，不能被裁切。</figcaption></figure><p>'+paragraph+'</p><table><tr><th>资源</th><th>呈现</th></tr><tr><td>CSS / PNG / SVG</td><td>原书排版</td></tr></table>')
    second = page('<h1 id="chapter">海边来信</h1>'+''.join(f'<p id="p{i}">{i+1:02d} · {paragraph * 2}</p>' for i in range(36))+'<h2 id="detail">深入阅读</h2><p>目录锚点必须跳到这一段。</p><a href="first.xhtml#picture">返回山海插图</a>')
    picture = page('<img src="art.png" alt="纯图片页"/>')
    css = '@font-face{font-family:BookQA;src:url(book.ttf)}body{font-family:BookQA,serif;font-size:20px;line-height:1.7;color:#243947;background:#fff}h1{font-size:1.8em;color:#225D78}figure{margin:0}img{width:100%;height:auto}figcaption{font-size:.7em}p{text-indent:2em}table{border-collapse:collapse}td,th{border:1px solid #778899;padding:8px}a{color:#225D78}'
    if fixed:
        first = page('<h1 style="position:absolute;left:50px;top:20px">固定版式 · 山海</h1><img style="position:absolute;left:50px;top:180px;width:900px;height:450px" src="art.png"/>', head='<meta name="viewport" content="width=1000,height=700"/>')
        second = first.replace('固定版式 · 山海', '固定版式 · 第二页')
        picture = first.replace('固定版式 · 山海', '固定版式 · 第三页')
    with zipfile.ZipFile(OUT / name, 'w') as z:
        z.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        for path, content in {'META-INF/container.xml':container,'OPS/package.opf':package,'OPS/first.xhtml':first,'OPS/second.xhtml':second,'OPS/image.xhtml':picture,'OPS/nav.xhtml':page(links),'OPS/style.css':css,'OPS/art.png':art_bytes,'OPS/book.ttf':font}.items():
            z.writestr(path, content, compress_type=zipfile.ZIP_DEFLATED)
    (RES / name).write_bytes((OUT / name).read_bytes())
    print(name, (OUT / name).stat().st_size)

# Standard IDPF font obfuscation is not encrypted book content.
key = hashlib.sha1(b'urn:qa:visual').digest()
obfuscated = bytes(value ^ key[index % len(key)] if index < 1040 else value for index, value in enumerate(font))
with zipfile.ZipFile(OUT / 'qa-illustrated.epub') as src, zipfile.ZipFile(RES / 'qa-obfuscated.epub', 'w') as dst:
    for info in src.infolist():
        dst.writestr(info, obfuscated if info.filename == 'OPS/book.ttf' else src.read(info.filename))
    dst.writestr('META-INF/encryption.xml', '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/><CipherData><CipherReference URI="OPS/book.ttf"/></CipherData></EncryptedData></encryption>')
