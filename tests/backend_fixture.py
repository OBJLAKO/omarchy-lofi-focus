"""Explicit backend selection for hermetic real CLI integration tests.

LOFI_TEST_BACKEND=python uses the retained reference implementation.
LOFI_TEST_BACKEND=rust requires SKYLOFI_NATIVE (an already-built executable).
No fixture starts audio from the installed plugin or builds during tests.
"""
import os
from pathlib import Path
import shutil


SOURCE = Path(os.environ.get('LOFI_TEST_SOURCE', Path(__file__).resolve().parents[1])).resolve()


def prepare_backend(plugin, env):
    backend = os.environ.get('LOFI_TEST_BACKEND', 'python')
    if backend not in ('python', 'rust'):
        raise ValueError('LOFI_TEST_BACKEND must be python or rust')
    entry = plugin / 'lofi-player'
    if backend == 'python':
        entry.write_text('#!/usr/bin/env python3\nimport sys\nsys.dont_write_bytecode = True\nfrom lofi_backend import main\nmain()\n')
        entry.chmod(0o755)
    else:
        source = Path(os.environ['SKYLOFI_NATIVE']).resolve()
        native = plugin / 'native/target/release/skylofi'
        native.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, native)
        native.chmod(0o755)
        env['SKYLOFI_NATIVE'] = str(native)
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    return backend
