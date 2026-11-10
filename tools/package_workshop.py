"""Build a draft official-loader package from the verified manual ZIP; never upload."""
from pathlib import Path
import json
import re
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
manifest = (root / 'release-files.txt').read_text().splitlines()
metadata = (root / 'workshop/Info.json').read_bytes()
info = json.loads(metadata)
assert re.fullmatch(r'[A-Za-z0-9]+', info['PackageName'])
assert info['PackageName'] == 'PalworldAutoProduction'
assert info['Version'] and info['DebugMode'] is False
assert info['InstallRule'] == [{'Type': 'Lua', 'Targets': ['./Scripts', './enabled.txt']}]
assert info['Dependencies'] == ['UE4SSExperimentalPW']
assert info['Thumbnail'] == 'thumbnail.png'
with ZipFile(root / 'releases/PalworldAutoProduction-Bases.zip') as manual:
    assert set(manual.namelist()) == {'PalworldAutoProduction/' + f for f in manifest}
    payload = {f: manual.read('PalworldAutoProduction/' + f) for f in manifest}
    for name, content in payload.items():
        assert content == (root / name).read_bytes(), f'Stale manual ZIP: {name}; run tools/package.py first'
payload['Info.json'] = metadata
payload['thumbnail.png'] = (root / 'docs/overview-preview.png').read_bytes()
assert payload['thumbnail.png'].startswith(b'\x89PNG\r\n\x1a\n')
dest = root / 'releases/PalworldAutoProduction-Workshop-draft.zip'
stage = dest.with_suffix('.zip.tmp')
with ZipFile(stage, 'w') as archive:
    for name, content in sorted(payload.items()):
        entry = ZipInfo(name, (1980, 1, 1, 0, 0, 0))
        entry.create_system = 3
        entry.external_attr = 0o100644 << 16
        archive.writestr(entry, content, compress_type=ZIP_DEFLATED, compresslevel=9)
with ZipFile(stage) as archive:
    assert set(archive.namelist()) == set(payload)
    for name, content in payload.items():
        assert archive.read(name) == content, name
stage.replace(dest)
print(f'Verified {len(payload)} files in {dest}; Workshop installation still needs a live test')
