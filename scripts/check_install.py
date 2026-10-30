#!/usr/bin/env python3
"""Smoke-test the installer in temporary directories, without launching the app."""
import os
import pathlib
import plistlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
installer = root / 'install.sh'
registry = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

def run(*arguments, expected=0):
    result = subprocess.run([str(installer), *map(str, arguments)], capture_output=True, text=True)
    assert result.returncode == expected, result.stdout + result.stderr
    return result.stdout

assert './install.sh' in run('--help')
run('--invalid-option', expected=2)
run('--no-build', root / 'dist', expected=1)
with tempfile.TemporaryDirectory(prefix='md-view-installer-') as directory:
    folder = pathlib.Path(directory)
    apps = folder / 'Applications with spaces'
    target = apps / 'MD View.app'
    try:
        run('--no-build', apps)
        assert os.access(target / 'Contents/MacOS/MDView', os.X_OK)
        assert os.access(target / 'Contents/MacOS/MermaidWorker', os.X_OK)
        with (target / 'Contents/Info.plist').open('rb') as stream:
            assert plistlib.load(stream)['CFBundleIdentifier'] == 'local.mdview.app'
        stale = target / 'Contents/Resources/obsolete-file'
        stale.write_text('Must disappear on update.')
        run('--no-build', apps)
        assert not stale.exists(), 'Update left stale resources'
        subprocess.run(['codesign', '--verify', '--strict', str(target)], check=True)
        assert not list(apps.glob('.md-view-install.*')), 'Staging directory was not cleaned'
        foreign = folder / 'Foreign Apps' / 'MD View.app/Contents'
        foreign.mkdir(parents=True)
        with (foreign / 'Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleIdentifier': 'unrelated.application'}, stream)
        run('--no-build', foreign.parents[1], expected=1)
        with (foreign / 'Info.plist').open('rb') as stream:
            assert plistlib.load(stream)['CFBundleIdentifier'] == 'unrelated.application'
        links = folder / 'Symlink Apps'
        links.mkdir()
        (links / 'MD View.app').symlink_to(target)
        run('--no-build', links, expected=1)
        assert (links / 'MD View.app').is_symlink()
    finally:
        subprocess.run([registry, '-u', str(target)], capture_output=True)
print('PASS: install, paths with spaces, clean update, signature, foreign-app and symlink protection.')
