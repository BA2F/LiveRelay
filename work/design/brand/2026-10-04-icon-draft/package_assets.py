"""Assemble a multi-resolution PNG-based ICO and a portable draft ZIP."""
from pathlib import Path
import struct
import zipfile
from PIL import Image

ROOT = Path(__file__).resolve().parent


def main():
    sizes = [16,24,32,48,64,128,256]
    images = [(n,(ROOT / f'software/png/icon-{n}.png').read_bytes()) for n in sizes]
    offset = 6 + 16 * len(images)
    entries = []
    for n, data in images:
        entries.append(struct.pack('<BBBBHHII', n if n < 256 else 0,
                                   n if n < 256 else 0, 0, 0, 1, 32, len(data), offset))
        offset += len(data)
    target = ROOT / 'software/windows/app_icon.ico'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(struct.pack('<HHH',0,1,len(images)) + b''.join(entries) + b''.join(d for _,d in images))
    with Image.open(target) as ico:
        assert ico.ico.sizes() == {(n,n) for n in sizes}
        for n in sizes:
            decoded = ico.ico.getimage((n,n)).convert('RGBA')
            with Image.open(ROOT / f'software/png/icon-{n}.png') as source:
                assert decoded.tobytes() == source.convert('RGBA').tobytes()
    archive = ROOT / 'LiveRelay-icon-draft.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(ROOT.rglob('*')):
            if p.is_file() and p != archive and 'qa' not in p.relative_to(ROOT).parts and '__pycache__' not in p.parts:
                z.write(p, 'LiveRelay-icon-draft/' + str(p.relative_to(ROOT)))
    print(f'Verified ICO frames {sizes}; packaged {archive.name}')


if __name__ == '__main__':
    main()
