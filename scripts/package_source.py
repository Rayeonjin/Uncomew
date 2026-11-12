#!/usr/bin/env python3
"""Package reviewed source roots, never the complete development directory."""
from pathlib import Path
import hashlib
import plistlib
import zipfile

ROOT = Path(__file__).resolve().parent.parent
TAG = 'v0.2.0-alpha.1'
DIRECTORIES = ('Sources', 'Resources', 'Tests', 'scripts', '.github')
FILES = ('.gitignore', 'Package.swift', 'README.md', 'LICENSE', 'CONTRIBUTING.md',
         'docs/BUILDING.md', 'docs/TESTING.md', 'docs/CHANGELOG.md', 'docs/REVIEW_CANDIDATES.md', 'build-app.sh', 'run-app.sh', 'setup.sh', 'rollback.sh')
EXTENSIONS = {'.swift', '.plist', '.sh', '.py', '.md', '.yml', '.yaml'}


def main():
    version = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
    if not TAG.startswith('v' + version + '-'):
        raise SystemExit('Release tag and app version disagree.')
    paths = [ROOT / name for name in FILES]
    paths.extend(ROOT.glob('test-*.sh'))
    for directory in DIRECTORIES:
        base = ROOT / directory
        if base.is_symlink() or not base.is_dir():
            raise SystemExit('Missing or symlinked source directory: ' + directory)
        for path in base.rglob('*'):
            if path.is_symlink():
                raise SystemExit('Refusing source symlink: ' + str(path.relative_to(ROOT)))
            if path.is_file() and path.suffix in EXTENSIONS:
                paths.append(path)
    paths = sorted(set(paths))
    for path in paths:
        if path.is_symlink() or not path.is_file():
            raise SystemExit('Missing or invalid release file: ' + str(path.relative_to(ROOT)))
    output = ROOT / 'releases'
    output.mkdir(exist_ok=True)
    archive = output / ('Uncomew-' + TAG + '-source.zip')
    temporary = archive.with_suffix('.zip.tmp')
    with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as bundle:
        for path in paths:
            bundle.write(path, 'Uncomew-' + TAG + '/' + path.relative_to(ROOT).as_posix())
    temporary.replace(archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(digest + '  ' + archive.name + '\n')
    print(str(archive))
    print(str(len(paths)) + ' source files; SHA-256 ' + digest)


if __name__ == '__main__':
    main()
