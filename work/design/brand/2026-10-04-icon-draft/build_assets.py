"""Rebuild the draft vector family and browser demo from three editable paths.

The supplied PNG is a visual reference, not the original vector artwork. These
curves are a manual reconstruction. This script never changes application files.
"""
from pathlib import Path
import json
import re
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
SOURCE = Path('/home/tahzun/Downloads/ChatGPT生成7暂定稿.png')
INK, GOLD, PAPER = '#272620', '#F3C477', '#F8F5ED'
# Coordinates measured in the 1254 × 1254 reference image, without either wordmark.
LEFT = 'M679 274 C669 289 656 297 642 304 L512 361 C480 378 461 397 461 428 L461 640 C461 662 474 676 496 685 L556 707 Q560 709 560 705 L560 540 C560 515 575 504 605 488 L645 465 C668 452 680 437 680 414 L680 276 Q680 273 679 274 Z'
RIGHT = 'M661 493 L749 529 C778 541 793 555 793 578 L793 698 Q793 709 781 709 C751 708 717 695 686 680 C669 672 661 660 661 644 Z'
FLAME = 'M619 477 C638 482 649 490 649 508 L649 579 C631 574 619 562 619 545 Z'
MICRO_FLAME = 'M615 477 C641 483 657 493 657 511 L657 579 C632 574 615 560 615 542 Z'


def normalize(path, shift_x=0):
    """All drawing commands use pairs of absolute coordinates."""
    tokens = re.findall(r'[MLCQZ]|-?\d+(?:\.\d+)?', path)
    axis = 0
    result = []
    for token in tokens:
        if token.isalpha():
            axis = 0
            result.append(token)
        else:
            value = (float(token) - (461 if axis == 0 else 274)) * .82
            value += (120 + shift_x * .82) if axis == 0 else 78
            result.append(f'{value:.2f}'.rstrip('0').rstrip('.'))
            axis = 1 - axis
    return ' '.join(result)


def shapes(micro=False, ink=INK, gold=GOLD, prefix='', traveler=False):
    paths = [normalize(LEFT), normalize(RIGHT, 14 if micro else 0),
             normalize(MICRO_FLAME if micro else FLAME)]
    classes = ['shell-left', 'shell-right', 'flame']
    ids = ['left-shell', 'right-shell', 'flame']
    out = ''.join(f'<path id="{prefix}{i}" class="{c}" fill="{color}" d="{d}"/>\n'
                  for i, c, color, d in zip(ids, classes, [ink, ink, gold], paths))
    if traveler:
        out += f'<path class="traveler" fill="{gold}" opacity="0" d="{paths[2]}"/>\n'
    return out


MOTION = '''
.flame { transform-box:fill-box; transform-origin:50% 50%; }
.traveler { transform-box:fill-box; transform-origin:50% 50%; }
.loading .flame { animation:breathe 1.8s ease-in-out infinite; }
.complete .flame { animation:lit .7s ease-out both; }
.complete .shell-left,.complete .shell-right { animation:settle .7s ease-out both; transform-box:fill-box; transform-origin:center; }
.relay .flame { animation:core-relay 1.6s ease-in-out both; }
.relay .traveler { animation:pass-light 1.6s cubic-bezier(.4,0,.2,1) both; }
.relay .shell-right { animation:receive 1.6s ease-in-out both; }
@keyframes breathe { 0%,100% {opacity:.5; transform:scaleY(.94)} 50% {opacity:1; transform:scaleY(1.035)} }
@keyframes lit { 0% {opacity:.35;transform:scale(.88)} 45% {opacity:1;transform:scale(1.1)} 100% {opacity:1;transform:scale(1)} }
@keyframes settle { 0% {transform:translateY(2px)} 65%,100% {transform:translateY(0)} }
@keyframes core-relay { 0%,25% {opacity:.4} 50%,100% {opacity:1} }
@keyframes pass-light { 0% {opacity:0;transform:translate(-56px,-18px) scale(.45)} 18% {opacity:.8} 45% {opacity:1;transform:translate(0,0) scale(.65)} 78% {opacity:1;transform:translate(57px,34px) scale(.5)} 100% {opacity:0;transform:translate(57px,34px) scale(.35)} }
@keyframes receive { 0%,58%,100% {fill:var(--ink, #272620)} 78% {fill:#B89962} }
@media (prefers-reduced-motion:reduce) { .loading .flame,.complete .flame,.complete .shell-left,.complete .shell-right,.relay .flame,.relay .traveler,.relay .shell-right {animation:none} }
'''


def svg(micro=False, inverse=False, mono=False, background=False, motion=None, prefix='', traveler=False):
    ink = PAPER if inverse else INK
    gold = ink if mono else ('#DBA042' if micro else GOLD)
    bg = INK if inverse else PAPER
    content = (f'<rect width="512" height="512" fill="{bg}"/>\n' if background else '')
    if motion:
        content += '<style>' + MOTION + '</style>\n'
    transform = ' transform="translate(-38.4 -38.4) scale(1.15)"' if micro else ''
    content += f'<g class="{motion or "brand-mark"}" style="--ink:{ink}"{transform}>\n'
    content += shapes(micro, ink, gold, prefix, traveler=traveler or motion == 'relay') + '</g>'
    return '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512" role="img" aria-label="留灯图案草案">\n' + content + '\n</svg>\n'


def save(path, text):
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8')
    return p


def main():
    variants = {
        'svg/mark-master.svg': {},
        'svg/mark-micro.svg': {'micro': True},
        'svg/mark-inverse.svg': {'inverse': True},
        'svg/mark-micro-inverse.svg': {'inverse': True, 'micro': True},
        'svg/mark-monochrome.svg': {'mono': True},
        'software/icon-square.svg': {'background': True},
        'software/icon-square-dark.svg': {'background': True, 'inverse': True},
        'software/icon-square-micro.svg': {'background': True, 'micro': True},
        'animations/loading.svg': {'motion': 'loading'},
        'animations/complete.svg': {'motion': 'complete'},
        'animations/handoff.svg': {'motion': 'relay'},
    }
    for name, options in variants.items():
        p = save(name, svg(**options))
        ET.parse(p)
    for n in [16,24,32,48,64,128,256,512]:
        save(f'svg/sizes/mark-{n}.svg', svg(micro=n <= 24).replace('width="512" height="512"', f'width="{n}" height="{n}"', 1))
    # Android resources remain examples outside the application source tree.
    # Fit the entire mark inside the central safe circle, including both lower corners.
    for mono, name in [(False, 'ic_launcher_foreground'), (True, 'ic_launcher_monochrome')]:
        paths = [normalize(LEFT), normalize(RIGHT), normalize(FLAME)]
        colors = [INK, INK, INK if mono else GOLD]
        content = '\n'.join(f'    <path android:fillColor="{c}" android:pathData="{d}"/>' for c, d in zip(colors, paths))
        save(f'software/android/res/drawable/{name}.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
  <group android:scaleX="0.1434375" android:scaleY="0.1434375"
      android:translateX="17.28" android:translateY="17.28">
{content}
  </group>
</vector>
''')
    save('software/android/res/drawable/ic_launcher_background.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
  <solid android:color="{PAPER}"/>
</shape>
''')
    for api in [26, 33]:
        mono = '\n  <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>' if api == 33 else ''
        save(f'software/android/res/mipmap-anydpi-v{api}/ic_launcher.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@drawable/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>{mono}
</adaptive-icon>
''')
    # Preview-only reference window: unchanged original PNG, shown without text.
    (ROOT / 'reference').mkdir(exist_ok=True)
    if SOURCE.exists():
        shutil.copyfile(SOURCE, ROOT / 'reference/original.png')
    manifest = {
        'status': 'manual reconstruction; design draft; not adopted in application',
        'source': SOURCE.name,
        'coordinate_system': 'viewBox 0 0 512 512',
        'colors': {'ink': INK, 'gold': GOLD, 'paper': PAPER, 'micro_gold': '#DBA042'},
        'layers': ['left-shell', 'right-shell', 'flame'],
        'micro_use': '16–24 logical pixels: 15% enlargement, wider flame, stronger gold, wider gap',
        'motion_ms': {'loading_loop': 1800, 'complete_once': 700, 'handoff_once': 1600},
        'application_files_modified': False,
    }
    save('manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    template = (ROOT / 'preview.template.html').read_text(encoding='utf-8')
    preview = template.replace('{{MOTION_CSS}}', MOTION)
    master = svg(prefix='preview-master-').replace('width="512" height="512"', 'class="art" width="512" height="512"', 1).replace(f' style="--ink:{INK}"','')
    preview = preview.replace('{{MASTER_MARK}}', master)
    for key, prefix in [('LOADING', 'loading'), ('COMPLETE', 'complete'), ('RELAY', 'relay')]:
        mark = svg(prefix=f'preview-{prefix}-', traveler=key == 'RELAY').replace(f' style="--ink:{INK}"','')
        preview = preview.replace('{{' + key + '_MARK}}', mark)
    sizes = ''.join(f'<div class="size"><img src="svg/mark-{"micro" if n <= 24 else "master"}.svg" data-size="{n}" width="{n}" height="{n}" alt="{n} 像素图案"><label>{n}px</label></div>' for n in [16,24,32,48,64,96,128])
    preview = preview.replace('{{SIZES}}', sizes)
    if '{{' in preview:
        raise ValueError('Unresolved template placeholder')
    save('preview.html', preview)
    print(f'Built {len(variants)} SVGs, Android examples, and manifest in {ROOT}')


if __name__ == '__main__':
    main()
