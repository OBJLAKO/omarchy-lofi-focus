#!/usr/bin/env python3
"""Collect unchanged license/notice texts from the locked native dependency graph.

Developer packaging tool, never run by the installed plugin. Missing crate
notices are reported rather than silently replaced with invented license text.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cargo', default='cargo')
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/native/THIRD-PARTY-NOTICES.txt')
    args = parser.parse_args()
    metadata = json.loads(subprocess.check_output([
        args.cargo, 'metadata', '--locked', '--offline', '--format-version', '1',
        '--filter-platform', 'x86_64-unknown-linux-gnu',
        '--manifest-path', str(ROOT / 'native/Cargo.toml')], text=True))
    nodes = {node['id']: node for node in metadata['resolve']['nodes']}
    visited = set()
    remaining = [metadata['resolve']['root']]
    while remaining:
        identity = remaining.pop()
        if identity in visited:
            continue
        visited.add(identity)
        remaining.extend(nodes[identity]['dependencies'])
    documents = {}
    packages = []
    missing = []
    for package in sorted(metadata['packages'], key=lambda p: (p['name'], p['version'])):
        if package['id'] not in visited or package['source'] is None:
            continue
        base = Path(package['manifest_path']).parent
        candidates = sorted({p for p in base.rglob('*') if p.is_file()
                             and p.name.upper().startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE'))
                             and not any(part in ('target', '.git') for part in p.relative_to(base).parts)})
        if package.get('license_file'):
            candidates.append(base / package['license_file'])
        references = []
        for path in dict.fromkeys(candidates):
            try:
                text = path.read_text(encoding='utf-8')
            except (OSError, UnicodeError):
                continue
            digest = hashlib.sha256(text.encode()).hexdigest()
            if digest not in documents:
                documents[digest] = text
            references.append((str(path.relative_to(base)), digest))
        if not references:
            missing.append(package['name'] + '@' + package['version'])
        packages.append((package, references))
    if missing:
        raise RuntimeError('No packaged notice text for: ' + ', '.join(missing))
    lines = ['Skylofi native dependency notices',
             'Collected from the x86_64 Linux dependency graph in native/Cargo.lock.',
             'Original notice texts are reproduced without modification.',
             'Identical documents are included once and referenced by SHA256.', '']
    for package, references in packages:
        lines.extend([package['name'] + ' ' + package['version'],
                      'Declared license: ' + str(package.get('license')),
                      'Source: https://crates.io/crates/' + package['name'] + '/' + package['version']])
        lines.extend('  ' + name + ' => ' + digest for name, digest in references)
        lines.append('')
    for digest, text in documents.items():
        lines.extend(['================================================================',
                      'Document SHA256: ' + digest, '', text, ''])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({'packages': len(packages), 'distinct_notice_documents': len(documents),
                      'bytes': args.output.stat().st_size, 'output': str(args.output)}))


if __name__ == '__main__':
    main()
