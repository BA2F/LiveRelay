#!/usr/bin/env python3
"""Verify exports and render the actual PDF. Run with bundled Python."""
from pathlib import Path
import json
import subprocess
import hashlib
import unicodedata
from urllib.parse import unquote
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont
from pypdf import PdfReader, PdfWriter

OUT=Path(__file__).resolve().parent
QA=OUT/'qa'
QA.mkdir(exist_ok=True)
DATA=json.loads((OUT/'evidence-index.json').read_text())
native=ET.parse(OUT/'LiveRelay-MVP0.4-system-architecture.drawio').getroot()
PDF=OUT/'LiveRelay-MVP0.4-system-architecture.pdf'
# Preserve the native diagram Subject; replace temporary export title.
reader=PdfReader(PDF)
writer=PdfWriter()
writer.clone_document_from_reader(reader)
writer.add_metadata({'/Title':'LiveRelay MVP0.4 System Architecture / 11 views','/Author':'LiveRelay','/Creator':'draw.io 30.2.4','/Keywords':'MVP0.4, 6fbee32, a586349, 2026-10-04'})
tmp=QA/'metadata.pdf'
with tmp.open('wb') as f: writer.write(f)
tmp.replace(PDF)
reader=PdfReader(PDF)
assert len(reader.pages)==11
results=[]
for i,page in enumerate(reader.pages):
    definition=DATA['pages'][i]
    text=subprocess.check_output(['pdftotext','-f',str(i+1),'-l',str(i+1),str(PDF),'-'],text=True)
    compact=''.join(unicodedata.normalize('NFKC',text).split())
    assert ''.join(unicodedata.normalize('NFKC',definition['title']).split()) in compact,(i,definition['title'])
    for v in ('6fbee32','a586349','2026-10-04','1.0.0+3'):
        assert v in compact,(i,v)
    assert f'{i+1:02d}/11' in compact
    cjk=sum('\u4e00'<=c<='\u9fff' for c in text)
    assert cjk>150
    with Image.open(OUT/'png'/f'{i+1:02d}-{definition["slug"]}.png') as im:
        assert im.size==(2702,1682),(i,im.size)
    svg=ET.parse(OUT/'svg'/f'{i+1:02d}-{definition["slug"]}.svg').getroot()
    assert svg.get('content')
    embedded=ET.fromstring(unquote(svg.get('content')))
    # draw.io embeds all pages in each SVG: require every visible native label
    # to correspond to this final source, including pages not rendered here.
    expected={c.get('id'):c.get('value') for c in native.iter('mxCell') if c.get('value')}
    actual={c.get('id'):c.get('value') for c in embedded.iter('mxCell') if c.get('value')}
    assert expected==actual,('stale embedded SVG',i+1)
    results.append(dict(page=i+1,title=definition['title'],pdfSizePoints=[float(page.mediabox.width),float(page.mediabox.height)],pngDimensions=[2702,1682],extractedChineseCharacters=cjk,titleAndVersionMatch=True))
subprocess.run(['pdftoppm','-r','90','-png',str(PDF),str(QA/'pdf-page')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
fontpath=subprocess.check_output(['fc-match','-f','%{file}','Noto Sans CJK SC'],text=True).strip()
font=ImageFont.truetype(fontpath,20)
for start in (0,6):
    count=min(6,11-start)
    sheet=Image.new('RGB',(1440,((count+1)//2)*485),'#e6edf1')
    draw=ImageDraw.Draw(sheet)
    for j in range(count):
        n=start+j+1
        with Image.open(QA/f'pdf-page-{n:02d}.png') as im:
            im=im.convert('RGB'); im.thumbnail((700,440))
            x,y=(j%2)*720+10,(j//2)*485+32
            sheet.paste(im,(x,y))
            draw.text((x,y-28),f'{n:02d}  {DATA["pages"][n-1]["title"]}',fill='#233c49',font=font)
    sheet.save(QA/f'pdf-contact-{start+1:02d}.png')
fonts=subprocess.check_output(['pdffonts',str(PDF)],text=True).splitlines()[2:]
assert fonts and all('yes yes yes' in ' '.join(line.split()) for line in fonts)
assert len(native.findall('diagram'))==11
assert not any('image=' in c.get('style','') for c in native.iter('mxCell'))
files=sorted(list(OUT.glob('*.drawio'))+list(OUT.glob('*.pdf'))+list((OUT/'png').glob('*.png'))+list((OUT/'svg').glob('*.svg'))+[OUT/'README.md',OUT/'evidence-index.md',OUT/'evidence-index.json',OUT/'native-structure-check.json',OUT/'build_architecture.py',OUT/'export_architecture.py',OUT/'verify_exports.py',QA/'visual-review.md'])
(OUT/'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(OUT)}\n' for p in files))
verification=dict(tool='draw.io 30.2.4 + Poppler + pypdf',nativePages=11,nativeRasterCount=0,pdfPages=11,pdfFontsEmbeddedWithUnicode=True,sourceCommit=DATA['sourceCommit'],documentationCommit=DATA['documentationCommit'],pages=results,visualInspection='See visual-review.md for the completed review.',pdfSHA256=hashlib.sha256(PDF.read_bytes()).hexdigest())
(QA/'verification.json').write_text(json.dumps(verification,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(dict(pdfPages=11,allPageTitlesAndVersionsMatch=True,chineseFontsEmbedded=True),ensure_ascii=False))
