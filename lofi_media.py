"""Identify dictation transport requests without blocking ordinary media keys."""
import json
import os
from pathlib import Path
import shutil


class DictationTransport:
    def __init__(self):
        self.suppressed = set()

    def ignore(self, method, pid, is_voxtype, ducking):
        if not is_voxtype or pid is None:
            return False
        if method == 'Pause' and ducking:
            self.suppressed.add(pid)
            return True
        if method == 'Play' and (ducking or pid in self.suppressed):
            self.suppressed.discard(pid)
            return True
        return False


def is_voxtype_process(pid):
    try:
        installed = shutil.which('voxtype')
        if not installed:
            return False
        return Path(f'/proc/{pid}/exe').resolve(strict=True) == Path(installed).resolve(strict=True)
    except (OSError, RuntimeError):
        return False


def ducking_enabled():
    path = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state')))/'sky.lofi/settings.json'
    try:
        return json.loads(path.read_text()).get('ducking', True) is not False
    except (OSError, ValueError):
        return True
