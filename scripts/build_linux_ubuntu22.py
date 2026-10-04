#!/usr/bin/env python3
"""Build a Linux candidate in a prepared Ubuntu 22.04 rootfs, then audit ABI."""

import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rootfs', type=Path, required=True)
    parser.add_argument('--flutter-sdk', type=Path, required=True)
    parser.add_argument('--pub-cache', type=Path, required=True)
    parser.add_argument('--build-number', type=int, required=True)
    args = parser.parse_args()
    root = args.rootfs.resolve()
    sdk = args.flutter_sdk.resolve()
    cache = args.pub_cache.resolve()
    app = Path(__file__).resolve().parents[1] / 'work/code/live_relay'
    if root == Path('/') or app.is_relative_to(root):
        parser.error('rootfs must be a separate, disposable directory')
    os_release = (root / 'etc/os-release').read_text()
    if not re.search(r'^ID=ubuntu$', os_release, re.M) or not re.search(
        r'^VERSION_ID="22\.04"$', os_release, re.M
    ):
        parser.error('a prepared Ubuntu 22.04 rootfs is required')
    if args.build_number <= 2:
        parser.error('candidate build number must exceed MVP0.3 build 2')
    for required in [sdk / 'bin/flutter', cache / 'hosted', root / 'usr/bin/clang']:
        if not required.exists():
            parser.error(f'missing prerequisite: {required}')
    # CMake caches absolute host include paths; never reuse a host build here.
    shutil.rmtree(app / 'build/linux/x64/release', ignore_errors=True)
    command = [
        'bwrap', '--bind', str(root), '/', '--unshare-user', '--uid', '0',
        '--gid', '0', '--unshare-pid', '--unshare-ipc', '--proc', '/proc',
        '--dev', '/dev', '--tmpfs', '/tmp', '--bind', str(app), str(app),
        '--bind', str(sdk), str(sdk), '--ro-bind', str(cache / 'hosted'),
        str(cache / 'hosted'), '--clearenv', '--setenv', 'HOME', '/root',
        '--setenv', 'PATH', f'{sdk}/bin:/usr/sbin:/usr/bin:/sbin:/bin',
        '--setenv', 'LANG', 'C.UTF-8', '--setenv', 'PUB_CACHE', str(cache),
        '--chdir', str(app), str(sdk / 'bin/flutter'), '--no-version-check',
        '--suppress-analytics', 'build', 'linux', '--release', '--no-pub',
        '--target', 'lib/main.dart', '--build-number', str(args.build_number),
    ]
    subprocess.run(command, check=True)
    bundle = app / 'build/linux/x64/release/bundle'
    report = {}
    limits = {'GLIBC': (2, 35), 'GLIBCXX': (3, 4, 30), 'CXXABI': (1, 3, 13)}
    for binary in [bundle / 'live_relay', *sorted((bundle / 'lib').glob('*.so*'))]:
        output = subprocess.check_output(['readelf', '-V', str(binary)], text=True)
        report[binary.name] = {}
        for namespace, limit in limits.items():
            versions = {
                tuple(map(int, value.split('.')))
                for value in re.findall(rf'\b{namespace}_([0-9.]+)', output)
            }
            maximum = max(versions) if versions else None
            report[binary.name][namespace] = (
                '.'.join(map(str, maximum)) if maximum else None
            )
            if maximum and maximum > limit:
                raise RuntimeError(f'{binary.name}: {namespace} {maximum} exceeds {limit}')
    print(json.dumps(report, indent=2))
    print(f'ABI audit passed; candidate bundle: {bundle}')


if __name__ == '__main__':
    main()
