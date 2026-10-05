#!/usr/bin/env python3
"""Export with native draw.io; normalize PDF pages to A3 landscape."""
from pathlib import Path
import json
import subprocess
from pypdf import PdfReader, PdfWriter

OUT=Path(__file__).resolve().parent
DATA=json.loads((OUT/'design-index.json').read_text())
ALL=OUT/'LiveRelay-总体目标架构.drawio'
SINGLE=OUT/'LiveRelay-系统总体架构.drawio'
LOG=[]

def export(source,fmt,dest,page=None):
    args=['/usr/bin/drawio','--export','--format',fmt,'--output',str(dest)]
    if page: args+=['--page-index',str(page)]
    if fmt=='png': args+=['--scale','1.5']
    elif fmt=='svg': args+=['--embed-diagram','--embed-svg-fonts','false','--svg-theme','light']
    elif fmt=='pdf': args+=['--all-pages','--crop','--embed-diagram']
    args+=[str(source)]
    r=subprocess.run(args,capture_output=True,text=True,timeout=60)
    LOG.append(dict(format=fmt,path=str(dest.relative_to(OUT)),returnCode=r.returncode,output=r.stdout+r.stderr))
    assert r.returncode==0 and dest.is_file(),LOG[-1]

for page in DATA['pages']:
    for fmt in ('png','svg'):
        (OUT/fmt).mkdir(exist_ok=True)
        export(ALL,fmt,OUT/fmt/f'{page["page"]:02d}-{page["slug"]}.{fmt}',page['page'])
    print(f'exported view {page["page"]}: PNG + SVG',flush=True)
for fmt in ('png','svg'):
    export(SINGLE,fmt,OUT/f'LiveRelay-系统总体架构.{fmt}',1)
for source,title in ((SINGLE,'LiveRelay 系统总体架构图'),(ALL,'LiveRelay 总体目标架构：系统、业务、应用、数据、技术')):
    pdf=source.with_suffix('.pdf')
    export(source,'pdf',pdf)
    reader=PdfReader(pdf); writer=PdfWriter()
    writer.clone_document_from_reader(reader)
    for page in writer.pages: page.scale_to(1190.551181,841.889764)
    writer.add_metadata({'/Title':title,'/Author':'LiveRelay','/Creator':'draw.io 30.2.4','/Keywords':'总体目标设计, 系统架构, 业务架构, 应用架构, 数据架构, 技术架构'})
    tmp=pdf.with_suffix('.normalized.pdf')
    with tmp.open('wb') as f: writer.write(f)
    tmp.replace(pdf)
(OUT/'qa').mkdir(exist_ok=True)
(OUT/'qa/export-log.json').write_text(json.dumps(LOG,ensure_ascii=False,indent=2)+'\n')
print('exported one-page system PDF and five-page architecture PDF (A3)',flush=True)
