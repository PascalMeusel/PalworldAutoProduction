"""Build and verify the manual-install UE4SS release using only tracked inputs."""
from pathlib import Path
import re
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
files = (root / "release-files.txt").read_text().splitlines()
if len(files) != len(set(files)) or any(not re.fullmatch(r"enabled\.txt|README\.md|LICENSE|Scripts/[a-z_]+\.lua", f) for f in files):
    raise ValueError("Invalid or duplicate entry in release-files.txt")
expected = {"enabled.txt", "README.md", "LICENSE", *(p.relative_to(root).as_posix() for p in (root / "Scripts").glob("*.lua"))}
if set(files) != expected:
    raise ValueError(f"Manifest mismatch: {expected ^ set(files)}")
dest = root / "releases/PalworldAutoProduction-Bases.zip"
dest.parent.mkdir(exist_ok=True)
stage = dest.with_suffix(".zip.tmp")
prefix = "PalworldAutoProduction/"
with ZipFile(stage, "w") as archive:
    for f in sorted(files):
        info = ZipInfo(prefix + f, (1980, 1, 1, 0, 0, 0))
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        archive.writestr(info, (root / f).read_bytes(), compress_type=ZIP_DEFLATED, compresslevel=9)
with ZipFile(stage) as archive:
    assert set(archive.namelist()) == {prefix + f for f in files}
    for f in files:
        if archive.read(prefix + f) != (root / f).read_bytes():
            raise ValueError(f"Bad release payload: {f}")
stage.replace(dest)
print(f"Verified {len(files)} files in {dest}")
