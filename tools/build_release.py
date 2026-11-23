"""Build a self-contained Windows installation ZIP using only repository files."""
from pathlib import Path
import hashlib
import zipfile
from check_release import check, ROOT

check()
name = 'CopperBalancing-Setup-0.2.1'
dist = ROOT / 'dist'
dist.mkdir(exist_ok=True)
files = [ROOT / x for x in ('README.md', 'LICENSE', 'Install.cmd', 'Uninstall.cmd', 'install.ps1', 'payload-sha256.json', 'TestBoard.PcbDoc', 'test-installer.ps1')]
for folder in ('source', 'docs', 'evidence', 'tools'):
    files.extend(p for p in (ROOT / folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc')
files.sort()
checksums = ''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.relative_to(ROOT).as_posix() + '\n' for p in files)
archive = dist / (name + '.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in files:
        z.write(p, name + '/' + p.relative_to(ROOT).as_posix())
    z.writestr(name + '/SHA256SUMS', checksums)
with zipfile.ZipFile(archive) as z:
    if z.testzip() is not None:
        raise ValueError('ZIP integrity failure')
(dist / 'SHA256SUMS.txt').write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + '  ' + archive.name + '\n')
print(archive)
