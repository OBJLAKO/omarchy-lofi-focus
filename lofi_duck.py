"""Optional VoxType ducking using its existing state file; no keybinding hooks."""
import json
import os
from pathlib import Path
import socket
import tomllib


class Ducker:
    def __init__(self):
        self.runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
        self.settings = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state'))) / 'sky.lofi/settings.json'
        self.config = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config'))) / 'voxtype/config.toml'
        self.last = {}

    def recording(self):
        state = self.runtime/'voxtype/state'
        try:
            with self.config.open('rb') as file:
                location = tomllib.load(file).get('state_file', 'auto')
            if location == 'disabled':
                return False
            if location != 'auto':
                state = Path(location).expanduser()
        except (OSError, ValueError):
            pass
        try:
            pid = int((self.runtime/'voxtype/pid').read_text().strip())
            os.kill(pid, 0)
            return state.read_text().strip() in ('recording', 'streaming')
        except (OSError, ValueError):
            return False

    def poll(self):
        try:
            settings = json.loads(self.settings.read_text())
        except (OSError, ValueError):
            return True
        factor = (0.2 if settings.get('ducking', True) and self.recording() else 1) * max(0, min(100, float(settings.get('masterVolume', 100)))) / 100
        for channel, key, default in [('main', 'mainVolume', 80), ('bg', 'bgVolume', 20)]:
            path = self.runtime/f'sky.lofi/sockets/{channel}.sock'
            try:
                stat = path.stat()
                volume = max(0, min(100, float(settings.get(key, default)))) * factor
                value = (stat.st_ino, volume)
                if self.last.get(channel) == value:
                    continue
                with socket.socket(socket.AF_UNIX) as client:
                    client.settimeout(0.05)
                    client.connect(str(path))
                    client.sendall((json.dumps({'command': ['set_property', 'volume', volume]})+'\n').encode())
                self.last[channel] = value
            except (OSError, ValueError, TypeError):
                self.last.pop(channel, None)
        return True

if __name__ == '__main__':
    import sys
    ducker = Ducker()
    try:
        settings = json.loads(ducker.settings.read_text())
    except (OSError, ValueError):
        settings = {}
    factor = (0.2 if settings.get('ducking', True) and ducker.recording() else 1) * max(0, min(100, float(settings.get('masterVolume', 100)))) / 100
    print(float(sys.argv[1]) * factor)
