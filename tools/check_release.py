"""Check the exact tested runtime payload and committed synthetic evidence."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check():
    payload = json.loads((ROOT / 'payload-sha256.json').read_text())
    for name, expected in payload.items():
        path = ROOT / name.replace('\\', '/')
        if sha(path) != expected:
            raise ValueError(f'Payload differs from native-tested 0.2.1: {name}')
    if sha(ROOT / 'install.ps1') != 'd5162da75dfc8dfcbc4991cea56db914902c86e97259bdd5ad299e7d614b5c88':
        raise ValueError('Installer differs from native-tested 0.2.1')
    evidence = json.loads((ROOT / 'evidence/native-verification.json').read_text())
    if evidence['status'] != 'PASS':
        raise ValueError('Native evidence is not PASS')
    for name, expected in evidence['sha256'].items():
        path = ROOT / name if name == 'TestBoard.PcbDoc' else ROOT / 'evidence' / name
        if sha(path) != expected:
            raise ValueError(f'Native fixture mismatch: {name}')
    for name in ('README.md', 'LICENSE', 'docs/VALIDATION.md', 'Install.cmd', 'Uninstall.cmd', 'test-installer.ps1'):
        if not (ROOT / name).is_file():
            raise FileNotFoundError(name)
    print('PASS: tested runtime hashes, fixture snapshots, and required release files')


if __name__ == '__main__':
    check()
