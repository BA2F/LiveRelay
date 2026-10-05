#!/usr/bin/env python3
"""Export the saved native source with the local draw.io installation."""
from pathlib import Path
import json
import subprocess
import sys

OUT = Path(__file__).resolve().parent
SOURCE = OUT / 'LiveRelay-MVP0.4-system-architecture.drawio'
DATA = json.loads((OUT / 'evidence-index.json').read_text())
selection = set(map(int, sys.argv[1:]))
logs = []
for page in DATA['pages']:
    number = page['number']
    if selection and number not in selection:
        continue
    for fmt in ('png', 'svg'):
        folder = OUT / fmt
        folder.mkdir(exist_ok=True)
        dest = folder / f'{number:02d}-{page["slug"]}.{fmt}'
        command = ['/usr/bin/drawio', '--export', '--format', fmt, '--page-index', str(number), '--output', str(dest)]
        command += ['--scale', '1.5'] if fmt == 'png' else ['--embed-diagram', '--embed-svg-fonts', 'false', '--svg-theme', 'light']
        command.append(str(SOURCE))
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        logs.append({'page':number,'format':fmt,'exitCode':result.returncode,'command':command,'log':result.stdout+result.stderr})
        if result.returncode or not dest.is_file():
            print(logs[-1],file=sys.stderr)
            raise SystemExit('draw.io export failed')
    print(f'exported page {number:02d}: PNG + SVG',flush=True)

pdf = OUT / 'LiveRelay-MVP0.4-system-architecture.pdf'
command = ['/usr/bin/drawio','--export','--format','pdf','--all-pages','--crop','--embed-diagram','--output',str(pdf),str(SOURCE)]
result = subprocess.run(command,capture_output=True,text=True,timeout=60)
logs.append({'format':'pdf','exitCode':result.returncode,'command':command,'log':result.stdout+result.stderr})
if result.returncode or not pdf.is_file():
    print(logs[-1],file=sys.stderr)
    raise SystemExit('draw.io PDF export failed')
(OUT / 'qa').mkdir(exist_ok=True)
(OUT / 'qa' / 'drawio-export-log.json').write_text(json.dumps(logs,ensure_ascii=False,indent=2)+'\n')
print('exported complete PDF',flush=True)
