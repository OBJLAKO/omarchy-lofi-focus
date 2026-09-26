"""Optional VoxType ducking using its existing state file; no keybinding hooks."""
import json
import os
from pathlib import Path
import socket
import time
import tomllib

# Ducking eases over roughly this long instead of snapping, so the mix dips
# under a dictation without a click. The ducked level itself is a setting
# (duckLevel, a percent kept while recording) so the music can stay audible.
DUCK_RAMP_SECONDS = 0.5
DUCK_DEFAULT_LEVEL = 35


class Ducker:
    def __init__(self):
        self.runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
        self.settings = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state'))) / 'sky.lofi/settings.json'
        self.config = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config'))) / 'voxtype/config.toml'
        self.last = {}
        self.duck_gain = 1.0
        self.duck_at = None

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

    def poll(self, skip=()):
        try:
            with self.settings.open() as source:
                settings = json.load(source)
                settings_revision = os.fstat(source.fileno()).st_mtime_ns
        except (OSError, ValueError):
            return True
        # Ease the duck gain toward its target so recording starts and stops
        # with a dip, not a click. Time-based so a slow worker still lands.
        now = time.monotonic()
        elapsed = (now - self.duck_at) if self.duck_at is not None else DUCK_RAMP_SECONDS
        self.duck_at = now
        duck_level = max(0.0, min(1.0, float(settings.get('duckLevel', DUCK_DEFAULT_LEVEL)) / 100))
        target_gain = duck_level if settings.get('ducking', True) and self.recording() else 1.0
        if self.duck_gain != target_gain:
            step = min(1.0, elapsed / DUCK_RAMP_SECONDS)
            self.duck_gain += (target_gain - self.duck_gain) * step
            if abs(self.duck_gain - target_gain) < 0.005:
                self.duck_gain = target_gain
        master = max(0, min(100, float(settings.get('masterVolume', 100)))) / 100
        factor = self.duck_gain * master
        channels = [('main', settings.get('mainVolume', 80)), ('bg', settings.get('bgVolume', 20))]
        layers = settings.get('natureLayers')
        if isinstance(layers, dict):
            for id, layer in layers.items():
                if not id.startswith('noise-') or not all(c.isalnum() or c == '-' for c in id):
                    continue
                channels.append(('nature-' + id, float(layer.get('volume', 25)) if settings.get('natureMixVersion') == 2 else float(layer.get('volume', 100)) * float(settings.get('natureVolume', 25)) / 100))
        else:
            channels.append(('noise', settings.get('noiseVolume', 25)))
        for channel, base_volume in channels:
            # A channel with an active fade owns its own volume; leave it alone
            # so the ramp is not overwritten on the next 100 ms tick.
            if channel in skip:
                continue
            path = self.runtime/f'sky.lofi/sockets/{channel}.sock'
            try:
                stat = path.stat()
                volume = max(0, min(100, float(base_volume))) * factor
                value = (stat.st_ino, stat.st_mtime_ns, settings_revision, round(self.duck_gain, 4), volume)
                if self.last.get(channel) == value:
                    continue
                with socket.socket(socket.AF_UNIX) as client:
                    client.settimeout(0.05)
                    client.connect(str(path))
                    client.sendall((json.dumps({'command': ['set_property', 'volume', volume], 'request_id': 1})+'\n').encode())
                    with client.makefile('r') as stream:
                        for line in stream:
                            reply = json.loads(line)
                            if reply.get('request_id') == 1:
                                if reply.get('error') != 'success': raise OSError('mpv rejected volume')
                                break
                        else: raise OSError('mpv disconnected')
                self.last[channel] = value
            except (OSError, ValueError, TypeError):
                self.last.pop(channel, None)
        return True

if __name__ == '__main__':
    import sys
    import fcntl
    import time
    ducker = Ducker()
    if sys.argv[1] == 'apply':
        ducker.poll()
    elif sys.argv[1] == '--watch':
        # This worker is independent of MPRIS/D-Bus name ownership.
        lock = (ducker.runtime/'sky.lofi/volume-worker.lock').open('w')
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            sys.exit(0)
        while True:
            ducker.poll()
            time.sleep(0.1)
    else:
        try:
            settings = json.loads(ducker.settings.read_text())
        except (OSError, ValueError):
            settings = {}
        factor = (0.2 if settings.get('ducking', True) and ducker.recording() else 1) * max(0, min(100, float(settings.get('masterVolume', 100)))) / 100
        print(float(sys.argv[1]) * factor)
