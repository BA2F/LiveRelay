#!/usr/bin/env python3
"""Validate native editability, current embedded sources, PDF text and exports."""
from pathlib import Path
import hashlib
import json
import subprocess
import unicodedata
from urllib.parse import unquote
import xml.etree.ElementTree as ET
from PIL import Image
from pypdf import PdfReader

OUT=Path(__file__).resolve().parent
QA=OUT/'qa'
DATA=json.loads((OUT/'design-index.json').read_text())

def compact(s): return ''.join(unicodedata.normalize('NFKC',s).split())

results=[]
for stem,count in [('LiveRelay-系统总体架构',1),('LiveRelay-总体目标架构',5)]:
    native=ET.parse(OUT/f'{stem}.drawio').getroot()
    pages=native.findall('diagram')
    assert len(pages)==count
    assert not any('image=' in c.get('style','') for c in native.iter('mxCell'))
    assert not any(c.get('style','').find('shape=image')>=0 for c in native.iter('mxCell'))
    for diagram in pages:
        cells=list(diagram.iter('mxCell'))
        ids={c.get('id') for c in cells}
        assert len(ids)==len(cells)
        for c in cells:
            if c.get('source'): assert c.get('source') in ids
            if c.get('target'): assert c.get('target') in ids
            if c.get('vertex')=='1':
                g=c.find('mxGeometry')
                x,y,w,h=[float(g.get(k,'0')) for k in ('x','y','width','height')]
                assert x>=0 and y>=0 and x+w<=2400 and y+h<=1700
    pdf=OUT/f'{stem}.pdf'
    reader=PdfReader(pdf)
    assert len(reader.pages)==count
    assert reader.metadata.get('/Creator')=='draw.io 30.2.4'
    assert reader.metadata.get('/Subject')
    fontlines=subprocess.check_output(['pdffonts',str(pdf)],text=True).splitlines()[2:]
    assert fontlines and all('yes yes yes' in ' '.join(l.split()) for l in fontlines)
    checks=[]
    for i,p in enumerate(reader.pages):
        text=subprocess.check_output(['pdftotext','-f',str(i+1),'-l',str(i+1),str(pdf),'-'],text=True)
        normalized=compact(text)
        assert compact(DATA['pages'][i]['title']) in normalized
        assert '总体目标设计v1.0' in normalized and '2026-10-04' in normalized
        for prohibited in ('已完成','未完成','待验证','已验证','MVP0.4','6fbee32','a586349'):
            assert prohibited not in normalized,(stem,i,prohibited)
        assert ('单张总图' if count==1 else f'{i+1:02d}/05') in normalized
        cjk=sum('\u4e00'<=c<='\u9fff' for c in text)
        assert cjk>150
        assert abs(float(p.mediabox.width)-1190.551181)<.01
        assert abs(float(p.mediabox.height)-841.889764)<.01
        if count==1:
            png=OUT/f'{stem}.png'; svg=OUT/f'{stem}.svg'
        else:
            basename=f'{i+1:02d}-{DATA["pages"][i]["slug"]}'
            png=OUT/'png'/f'{basename}.png'; svg=OUT/'svg'/f'{basename}.svg'
        with Image.open(png) as image: assert image.size==(3602,2552)
        root=ET.parse(svg).getroot()
        assert root.get('content')
        embedded=ET.fromstring(unquote(root.get('content')))
        expected={c.get('id'):c.get('value') for c in native.iter('mxCell') if c.get('value')}
        actual={c.get('id'):c.get('value') for c in embedded.iter('mxCell') if c.get('value')}
        assert expected==actual,(stem,i,'stale embedded source')
        checks.append(dict(page=i+1,title=DATA['pages'][i]['title'],pdfChineseCharacters=cjk,pngDimensions=[3602,2552],embeddedSVGCurrent=True))
    prefix='single-pdf' if count==1 else 'set-pdf'
    subprocess.run(['pdftoppm','-r','90','-png',str(pdf),str(QA/prefix)],check=True,capture_output=True)
    results.append(dict(file=f'{stem}.pdf',nativePages=count,pdfPages=count,paper='A3 landscape',fontsEmbeddedUnicode=True,nativeRasterCount=0,checks=checks))

verification=dict(date='2026-10-04',purpose='总体目标设计',tools='draw.io 30.2.4 / Poppler / pypdf',results=results,visualReview='visual-review.md')
(QA/'verification.json').write_text(json.dumps(verification,ensure_ascii=False,indent=2)+'\n')
files=sorted(list(OUT.glob('*.drawio'))+list(OUT.glob('*.pdf'))+list(OUT.glob('*.png'))+list(OUT.glob('*.svg'))+list(OUT.glob('*.md'))+list(OUT.glob('*.json'))+list(OUT.glob('*.py'))+list((OUT/'png').glob('*.png'))+list((OUT/'svg').glob('*.svg'))+list(QA.glob('*.json'))+list(QA.glob('*.md')))
(OUT/'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(OUT)}\n' for p in files))
print(json.dumps(dict(nativeEditable=True,pdfPages=[1,5],paper='A3 landscape',titlesAndFontsVerified=True,pngDimensions=[3602,2552]),ensure_ascii=False))
