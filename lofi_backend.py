"""Serialized playback control and recovery using Omarchy's existing Python/mpv.

Settings describe the mix; session.json records playback intent. A single worker
handles ducking and recovery, independently of the panel and MPRIS bus ownership.
"""
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import shutil
import select
import socket
import subprocess
import sys
import time
import tempfile
import stat

from lofi_youtube import canonical_url, clean_title, saved_entries, MAX_SAVED
from lofi_config import read_json, level, preferences, session_state
from lofi_duck import Ducker
from lofi_feed import resolve as resolve_playlist

ROOT = Path(__file__).resolve().parent
WORKER_VERSION = hashlib.sha256(Path(__file__).read_bytes() + (ROOT/'lofi_duck.py').read_bytes() + (ROOT/'lofi_youtube.py').read_bytes() + (ROOT/'lofi_config.py').read_bytes()).hexdigest()
RETRY_DELAYS = (2, 5, 10, 20, 30)
CONNECT_TIMEOUT = 15
STABLE_SECONDS = 30
# Gentle ramps: a stream should ease in when it starts and ease out before it
# stops, so the mix never cuts in or dies abruptly.
FADE_IN_SECONDS = 2.5
FADE_OUT_SECONDS = 1.6


def ease(progress):
    """Smoothstep, so a ramp accelerates and settles instead of moving linearly."""
    return progress * progress * (3 - 2 * progress)


def write_json(path, value):
    text = json.dumps(value, indent=2, ensure_ascii=False) + '\n'
    try:
        if path.read_text() == text:
            return
    except OSError:
        pass
    # Unique, exclusively created files cannot follow a stale .tmp symlink.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent,
                                         prefix=path.name + '.', delete=False) as output:
            temporary = Path(output.name)
            output.write(text)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def log_control(runtime, event):
    """Small rotating transport log, with no audio or dictated text."""
    try:
        path = runtime/'logs'/'control.log'
        if path.exists() and path.stat().st_size > 65536:
            path.replace(path.with_suffix('.log.previous'))
        event['time'] = time.strftime('%Y-%m-%dT%H:%M:%S%z')
        with path.open('a') as output:
            output.write(json.dumps(event) + '\n')
    except OSError:
        pass  # Diagnostics must never prevent Pause or Stop.


def ipc(path, command):
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(.15)
            client.connect(str(path))
            client.sendall((json.dumps({'command': command, 'request_id': 1}) + '\n').encode())
            with client.makefile() as stream:
                deadline = time.monotonic() + 1
                for _ in range(64):
                    line = stream.readline(1024 * 1024 + 1)
                    if not line or len(line) > 1024 * 1024 or time.monotonic() > deadline:
                        return None
                    reply = json.loads(line)
                    if not isinstance(reply, dict):
                        return None
                    if reply.get('request_id') == 1:
                        return reply.get('data') if reply.get('error') == 'success' else None
    except (OSError, ValueError, RecursionError):
        pass
    return None


def fetch_number(sock, prop):
    """Read a numeric mpv property, returning None when it is unset (e.g. live)."""
    value = ipc(sock, ['get_property', prop])
    return float(value) if isinstance(value, (int, float)) and math.isfinite(value) else None


class Player:
    def __init__(self):
        self.runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'sky.lofi'
        self.settings_dir = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state'))) / 'sky.lofi'
        self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        info = self.runtime.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError('Playback runtime must be an owned directory, not a symlink')
        self.runtime.chmod(0o700)
        self.settings_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        for name in ('sockets', 'logs'):
            (self.runtime/name).mkdir(exist_ok=True)
        self.reload_catalog()
        self.settings = {}
        self.session = {}
        self.lock = (self.runtime/'control.lock').open('w')
        self.ducker = Ducker()
        # Fades live in their own file and lock: the volume worker steps them
        # ten times a second, while control commands only request them. Keeping
        # them out of settings/session avoids re-reading those on every tick.
        self.fades_path = self.runtime/'fades.json'
        self.fades_lock = (self.runtime/'fades.lock').open('w')
        self.fades = read_json(self.fades_path, {})

    def reload_catalog(self):
        catalog = read_json(ROOT/'stations.json', {})
        categories = catalog.get('categories', [])
        self.stations = {}
        for category in categories if isinstance(categories, list) else []:
            if not isinstance(category, dict) or not all(isinstance(category.get(k), str) for k in ('id', 'name')):
                continue
            stations = category.get('stations', [])
            for station in stations if isinstance(stations, list) else []:
                if (isinstance(station, dict) and all(isinstance(station.get(k), str) for k in ('id', 'name', 'url'))
                        and station['id'] and len(station['id']) <= 80
                        and all(c.isascii() and (c.isalnum() or c == '-') for c in station['id'])):
                    self.stations[station['id']] = dict(station, category=category['id'], category_name=category['name'])
        self.music = [s for s in self.stations if self.stations[s]['category'] == 'lofi']
        self.nature = [s for s in self.stations if self.stations[s]['category'] == 'ambience']

    def add_saved_sources(self):
        for entry in self.settings.get('youtube', []):
            self.stations[entry['id']] = dict(entry, category='youtube', category_name='YouTube')
        self.music = [s for s in self.stations if self.stations[s]['category'] in ('lofi', 'youtube')]

    def is_youtube(self):
        station = self.stations.get(self.session.get('station'), {})
        return station.get('category') == 'youtube' or station.get('kind') == 'youtube'

    def voice_available(self):
        # Built-in radio can use YouTube extraction and still accept voice.
        # Saved YouTube sources keep their dedicated listening policy.
        station = self.stations.get(self.session.get('station'), {})
        return station.get('category') != 'youtube'

    def remember_youtube(self, force=False):
        if not self.is_youtube() or not self.alive('main'):
            return
        now = time.monotonic()
        if not force and now - self.session.get('bookmark_at', 0) < 10:
            return
        title = ipc(self.sock('main'), ['get_property', 'media-title'])
        position = fetch_number(self.sock('main'), 'time-pos')
        duration = fetch_number(self.sock('main'), 'duration')
        if position is None:
            return
        live = str(ipc(self.sock('main'), ['get_property', 'metadata/by-key/ytdl_is_live'])).lower() in ('true', 'yes', '1')
        if live:
            position, duration = 0, 1
        self.session['bookmark_at'] = now
        for entry in self.settings['youtube']:
            if entry['id'] != self.session['station']:
                continue
            if isinstance(title, str) and title and not title.startswith(('http:', 'https:')):
                # An explicit user label stays intact; only fill the generated name.
                if entry['name'].startswith('YouTube · '):
                    entry['name'] = clean_title(title)
                    self.stations[entry['id']]['name'] = entry['name']
            if position is not None and duration is not None and duration > 0:
                entry['position'] = round(position, 1) if 0 <= position < duration - 5 else 0
                self.stations[entry['id']]['position'] = entry['position']

    def acquire(self, blocking=True):
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError:
            return False
        self.reload_catalog()
        self.settings = preferences(read_json(self.settings_dir/'settings.json', read_json(ROOT/'settings.json', {})))
        for key, value in dict(defaultStation='lofi-lilo', mainVolume=65, bgVolume=20,
                               bgStation='talk-bbc-world', mix=True, masterVolume=100, ducking=True).items():
            self.settings.setdefault(key, value)
        # Look-and-feel preferences. The panel reads them from status.json and
        # writes them back through the `ui` command; the backend only stores
        # them, so every setting survives restarts and stays CLI-addressable.
        for key, value in dict(animations=True, revealAnimations=True, steamAnimation=True,
                               glowAnimation=True, equalizerAnimation=True, fadeEnabled=True,
                               fadeSeconds=3, revealSpeed=1, collapsibleSections=True,
                               duckLevel=35).items():
            self.settings.setdefault(key, value)
        self.settings['youtube'] = saved_entries(self.settings.get('youtube'))
        self.add_saved_sources()
        previous_default = self.settings['defaultStation']
        if previous_default not in self.music:
            self.settings['defaultStation'] = self.music[0] if self.music else ''
        # Preserve the old single ambience selection and its effective volume.
        if 'natureLayers' not in self.settings:
            old = self.settings.get('noiseStation', 'off')
            self.settings['natureVolume'] = self.settings.get('noiseVolume', 25)
            self.settings['natureLayers'] = {old: {'enabled': True, 'volume': 100}} if old in self.nature else {}
        self.settings.setdefault('natureVolume', 25)
        if self.settings.get('natureMixVersion') != 2:
            gain = level(self.settings['natureVolume'], 25) / 100
            for layer in self.settings['natureLayers'].values():
                layer['volume'] = round(level(layer.get('volume', 100)) * gain, 6)
            self.settings['natureMixVersion'] = 2
            self.settings['natureVolume'] = 100  # Legacy CLI field; audio uses direct layer levels.
        self.session = session_state(read_json(self.runtime/'session.json', {}))
        if not self.session:
            active = any(self.alive(c) for c in self.channels(include_legacy=True))
            paused = (self.runtime/'paused.flag').exists()
            self.session = {'mode': 'paused' if active and paused else ('playing' if active else 'stopped'),
                            'station': previous_default, 'attempts': 0,
                            'started': time.monotonic(), 'retry_due': 0}
        if self.session.get('station') not in self.music:
            # A catalog update can retire the station while its mpv is still
            # alive. Replace that audio as well as its label, keeping session
            # intent and the independent voice/nature processes unchanged.
            self.stop_channel('main')
            self.session.update(station=self.settings['defaultStation'], attempts=0,
                                retry_due=0, playing_since=0, last_position=None)
            if self.session['mode'] == 'playing':
                self.start_music()
        self.save()
        return True

    def release(self):
        fcntl.flock(self.lock, fcntl.LOCK_UN)

    def save(self):
        write_json(self.settings_dir/'settings.json', self.settings)
        write_json(self.runtime/'session.json', self.session)

    def sock(self, channel):
        return self.runtime/'sockets'/f'{channel}.sock'

    def channels(self, include_legacy=False):
        return ['main', 'bg'] + ['nature-' + s for s in self.nature] + (['noise'] if include_legacy else [])

    def socket_matches(self, channel, argv):
        """Match only this runtime; another checkout owns its own processes."""
        current = ('--input-ipc-server=' + str(self.sock(channel))).encode()
        return current in argv

    def matches_process(self, channel, pid):
        try:
            argv = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
            if channel == 'volume':
                return (b'--watch' in argv and any(str(ROOT/name).encode() in argv
                        for name in ('lofi-player', 'lofi_duck.py')))
            if channel == 'mpris':
                return str(ROOT/'lofi-mpris').encode() in argv
            if channel == 'feed':
                return str(ROOT/'lofi-player').encode() in argv and b'--resolve-feed' in argv
            return self.socket_matches(channel, argv)
        except OSError:
            return False

    def alive(self, channel):
        try:
            pid = int((self.runtime/f'{channel}.pid').read_text())
            return pid > 0 and self.matches_process(channel, pid)
        except (OSError, ValueError):
            return False

    def terminate(self, handle):
        """SIGTERM then SIGKILL a process pinned by pidfd, never a numeric PID."""
        exited = select.poll()
        exited.register(handle, select.POLLIN)
        try:
            signal.pidfd_send_signal(handle, signal.SIGTERM)
            if not exited.poll(250):
                signal.pidfd_send_signal(handle, signal.SIGKILL)
                exited.poll(250)
        except ProcessLookupError:
            pass  # The pinned process exited; never follow a reused PID.

    def terminate_audio(self, pid, handle):
        """Stop mpv and its extractor tree without process-group/PID signals.

        YouTube's synchronous Lua hook can outlive mpv's short shutdown grace.
        Freeze each pinned parent before discovering children so extraction
        cannot fork new helpers while the tree is being stopped.
        """
        try:
            argv = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
        except OSError:
            return
        if b'--ytdl=yes' not in argv:
            self.terminate(handle)
            return
        pinned = []
        frozen = []

        def freeze(process, descriptor):
            signal.pidfd_send_signal(descriptor, signal.SIGSTOP)
            frozen.append(descriptor)
            poll = select.poll()
            poll.register(descriptor, select.POLLIN)
            deadline = time.monotonic() + .3
            while not poll.poll(0):
                status = Path(f'/proc/{process}/status').read_text()
                state = next(line for line in status.splitlines() if line.startswith('State:'))
                if state.split(':', 1)[1].split()[0] in ('T', 't'):
                    break
                if time.monotonic() >= deadline:
                    raise OSError('Could not suspend the YouTube extractor safely')
                time.sleep(.005)
            if poll.poll(0):
                return
            children = set()
            for task in Path(f'/proc/{process}/task').iterdir():
                try:
                    children.update(int(n) for n in (task/'children').read_text().split())
                except FileNotFoundError:
                    continue
            for child in children:
                if len(pinned) >= 64:
                    raise OSError('Unexpectedly large extractor process tree')
                try:
                    child_handle = os.pidfd_open(child)
                except ProcessLookupError:
                    continue
                pinned.append(child_handle)
                try:
                    status = Path(f'/proc/{child}/status').read_text()
                except FileNotFoundError:
                    continue
                parent = next(line for line in status.splitlines() if line.startswith('PPid:'))
                if int(parent.split()[1]) == process and not poll.poll(0):
                    try:
                        freeze(child, child_handle)
                    except (ProcessLookupError, FileNotFoundError):
                        continue

        try:
            freeze(pid, handle)
            for descriptor in reversed(frozen[1:]):
                try:
                    signal.pidfd_send_signal(descriptor, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            self.terminate(handle)
        except ProcessLookupError:
            pass
        finally:
            # On errors, never leave a surviving process suspended.
            for descriptor in reversed(frozen):
                try:
                    signal.pidfd_send_signal(descriptor, signal.SIGCONT)
                except ProcessLookupError:
                    pass
            for descriptor in pinned:
                os.close(descriptor)

    def plugin_pids(self, channel):
        """Yield PIDs whose command line carries this channel's socket marker."""
        try:
            entries = list(os.scandir('/proc'))
        except OSError:
            return
        for entry in entries:
            if not entry.name.isdigit():
                continue
            try:
                argv = Path(entry.path, 'cmdline').read_bytes().split(b'\0')
            except OSError:
                continue
            if self.socket_matches(channel, argv):
                yield int(entry.name)

    def process_socket(self, channel, pid):
        """Return the channel socket this process was started with, or None."""
        try:
            argv = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
        except OSError:
            return None
        current = str(self.sock(channel)).encode()
        for argument in argv:
            if argument.startswith(b'--input-ipc-server='):
                path = argument[len(b'--input-ipc-server='):]
                if path == current:
                    return path
        return None

    def reap(self, channel, orphan_only=False):
        """Terminate audio belonging to this runtime, including lost PID files.

        Pin candidates before verifying their identity and signalling. Never
        claim a foreign runtime, even if its directory has been deleted.
        """
        if channel in ('volume', 'mpris', 'feed'):
            return
        own_pid = os.getpid()
        current = str(self.sock(channel)).encode()
        for pid in self.plugin_pids(channel):
            if pid == own_pid:
                continue
            socket_path = self.process_socket(channel, pid)
            if socket_path is None:
                continue
            # A live runtime directory means an instance still owns this
            # process, so only a normal stop may reap our own channel; a
            # crashing worker and foreign instances leave it alone. The
            # directory exists as soon as an instance starts, unlike the socket
            # file, so this never mistakes a just-started stream for an orphan.
            if os.path.isdir(os.path.dirname(socket_path)):
                if orphan_only or socket_path != current:
                    continue
            try:
                handle = os.pidfd_open(pid)
            except OSError:
                continue
            try:
                if self.matches_process(channel, pid):
                    self.terminate_audio(pid, handle)
            finally:
                os.close(handle)

    def live_channels(self):
        """Yield channel names found in live processes' socket markers.

        Unlike channels(), this does not depend on the catalog, so it still
        finds nature layers after a wiped or updated stations.json.
        """
        try:
            entries = list(os.scandir('/proc'))
        except OSError:
            return
        for entry in entries:
            if not entry.name.isdigit():
                continue
            try:
                argv = Path(entry.path, 'cmdline').read_bytes().split(b'\0')
            except OSError:
                continue
            for argument in argv:
                if not (argument.startswith(b'--input-ipc-server=')
                        and argument.startswith(('--input-ipc-server=' + str(self.runtime/'sockets') + '/').encode())):
                    continue
                name = argument.rsplit(b'/', 1)[-1]
                if name.endswith(b'.sock'):
                    yield name[:-len(b'.sock')].decode(errors='replace')

    def reap_orphans(self, orphan_only=False):
        """Reap leftover audio for every channel this plugin can play.

        Called when the worker retires, so a wiped runtime directory cannot
        leave detached mpv processes behind. Channels come from both the
        catalog and live processes, so a removed or unreadable stations.json
        cannot hide audio. Foreign live controllers are left alone; see reap().
        """
        channels = list(self.channels(include_legacy=True))
        seen = set(channels)
        for channel in self.live_channels():
            if channel not in seen:
                seen.add(channel)
                channels.append(channel)
        for channel in channels:
            self.reap(channel, orphan_only=orphan_only)

    def stop_channel(self, channel):
        if hasattr(self, 'fades_lock'):
            fcntl.flock(self.fades_lock, fcntl.LOCK_EX)
            try:
                fades = read_json(self.fades_path, {})
                if channel in fades:
                    fades.pop(channel)
                    write_json(self.fades_path, fades)
            finally:
                fcntl.flock(self.fades_lock, fcntl.LOCK_UN)
        pid_path = self.runtime/f'{channel}.pid'
        try:
            pid = int(pid_path.read_text())
        except (FileNotFoundError, ValueError):
            pid = 0
        if pid > 0:
            try:
                # Pin before inspecting /proc. Both signals and exit polling use
                # this same handle, never a numeric PID or process-group fallback.
                handle = os.pidfd_open(pid)
            except ProcessLookupError:
                handle = None
            if handle is not None:
                try:
                    if self.matches_process(channel, pid):
                        self.terminate_audio(pid, handle)
                finally:
                    os.close(handle)
        # The PID file is the fast path, never the only one: reap by socket
        # marker so a missing PID file can no longer orphan audio.
        self.reap(channel)
        pid_path.unlink(missing_ok=True)
        self.sock(channel).unlink(missing_ok=True)

    def spawn(self, channel, url, volume, loop=False, paused=False, fade_in=False, youtube=False, position=0):
        if youtube:
            url = canonical_url(str(url))
            if not shutil.which('yt-dlp'):
                raise ValueError('YouTube playback needs yt-dlp. Install or update it, then retry.')
        self.stop_channel(channel)
        log = self.runtime/'logs'/f'{channel}.log'
        if log.exists():
            log.replace(log.with_suffix('.log.previous'))
        # A new stream starts silent and ramps up, so it glides in rather than
        # popping. The worker owns its volume until the ramp finishes.
        fading = fade_in and not paused and self.settings.get('fadeEnabled', True)
        start_volume = 0 if fading else volume
        # Warnings/errors and lifecycle messages, not every IPC request.
        args = ['mpv', '--no-config', '--no-video', '--terminal=yes', '--input-terminal=no', '--load-scripts=no',
                '--ytdl=no', '--audio-display=no', '--msg-level=all=warn,cplayer=info',
                '--msg-color=no', '--term-status-msg=', '--network-timeout=12', '--tls-verify=yes',
                f'--volume={start_volume}', f'--input-ipc-server={self.sock(channel)}',
                '--user-agent=sky.lofi/1.0 (mpv)']
        if youtube:
            args.remove('--ytdl=no')
            args += ['--ytdl=yes', '--ytdl-format=bestaudio', '--keep-open=yes', '--sid=no',
                     '--script-opts=ytdl_hook-ytdl_path=' + shutil.which('yt-dlp') + ',ytdl_hook-force_all_formats=no',
                     '--ytdl-raw-options=ignore-config=,no-plugin-dirs=,no-remote-components=,no-playlist=,socket-timeout=10,retries=1,extractor-retries=1']
            if position > 0:
                args.append('--start=' + str(position))
        if loop:
            args.append('--loop-file=inf')
        if paused:
            args.append('--pause')
        with log.open('wb') as output:
            child = subprocess.Popen(args + ['--', str(url)], stdin=subprocess.DEVNULL,
                                     stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        (self.runtime/f'{channel}.pid').write_text(str(child.pid) + '\n')
        for _ in range(30):
            if self.sock(channel).exists() or child.poll() is not None:
                break
            time.sleep(.01)
        if fading:
            self.request_fade(channel, self.fade_in_seconds(), wait_ready=youtube)

    def fade_in_seconds(self):
        return level(self.settings.get('fadeSeconds', FADE_IN_SECONDS), FADE_IN_SECONDS)

    def fade_out_seconds(self):
        # A touch shorter than the ramp in, but never zero unless disabled.
        return level(self.settings.get('fadeSeconds', FADE_OUT_SECONDS * 1.8), 3) * 0.6

    def effective(self, base):
        # Target the ducked level directly from settings, not the ducker's
        # in-flight gain: this runs in the CLI process, where that gain is
        # fresh. The volume worker still eases the mix to whatever we pick.
        ducked = self.settings.get('ducking', True) and self.ducker.recording()
        gain = level(self.settings.get('duckLevel', 35), 35) / 100 if ducked else 1.0
        return level(base) * level(self.settings['masterVolume'], 100) / 100 * gain

    def channel_volume(self, channel):
        if channel == 'main':
            return self.settings['mainVolume']
        if channel == 'bg':
            return self.settings['bgVolume']
        return self.settings['natureLayers'].get(channel.removeprefix('nature-'), {}).get('volume', 25)

    def request_fade(self, channel, duration, silence=False, wait_ready=False):
        """Store a gain envelope; ducking and mix levels remain authoritative."""
        if not self.alive(channel):
            return
        current = ipc(self.sock(channel), ['get_property', 'volume'])
        base = self.effective(self.channel_volume(channel))
        start = level(current) / base if base > 0 else 0.0
        target_gain = 0.0 if silence else 1.0
        fcntl.flock(self.fades_lock, fcntl.LOCK_EX)
        try:
            self.fades = read_json(self.fades_path, {})
            self.fades[channel] = dict(gain_from=max(0.0, min(1.0, start)),
                                       gain_to=target_gain, started=time.monotonic(), await_ready=wait_ready,
                                       duration=max(0.0, float(duration)) if self.fade_configured() else 0.0)
            write_json(self.fades_path, self.fades)
        finally:
            fcntl.flock(self.fades_lock, fcntl.LOCK_UN)

    def fade_out_all(self, duration=FADE_OUT_SECONDS):
        for channel in self.channels(include_legacy=True):
            if self.alive(channel):
                self.request_fade(channel, duration, silence=True)

    def fade_in_channel(self, channel, duration=FADE_IN_SECONDS):
        if self.alive(channel):
            self.request_fade(channel, duration, wait_ready=channel == 'main' and self.is_youtube())

    def step_fades(self):
        """Return channel gains, holding silence until Pause/Stop is committed."""
        fcntl.flock(self.fades_lock, fcntl.LOCK_EX)
        try:
            fades = read_json(self.fades_path, {})
            if not isinstance(fades, dict):
                fades = {}
            gains = {}
            now = time.monotonic()
            for channel, fade in list(fades.items()):
                # Old absolute-volume ramps cannot safely override current levels.
                if not isinstance(fade, dict) or 'gain_to' not in fade or not self.alive(channel):
                    fades.pop(channel, None)
                    continue
                if fade.get('await_ready'):
                    if fetch_number(self.sock(channel), 'time-pos') is None:
                        gains[channel] = 0.0
                        continue
                    fade.update(await_ready=False, started=now)
                duration = level(fade.get('duration'), 0)
                started = fade.get('started', now)
                if not isinstance(started, (int, float)) or not math.isfinite(started):
                    started = now
                progress = max(0.0, min(1.0, (now - started) / duration)) if duration else 1.0
                start = min(1.0, level(fade.get('gain_from')))
                target = min(1.0, level(fade.get('gain_to')))
                gains[channel] = start + (target - start) * ease(progress)
                if progress >= 1.0 and target > 0:
                    fades.pop(channel, None)
            if fades != read_json(self.fades_path, {}):
                write_json(self.fades_path, fades)
            self.fades = fades
            return gains
        finally:
            fcntl.flock(self.fades_lock, fcntl.LOCK_UN)

    def start_music(self, reset=True):
        if self.session.get('station') not in self.stations:
            self.session['mode'] = 'stopped'
            return
        station = self.stations[self.session['station']]
        options = dict(fade_in=True)
        if station['category'] == 'youtube' or station.get('kind') == 'youtube':
            options.update(youtube=True, position=station.get('position', 0))
        self.spawn('main', station['url'], self.effective(self.settings['mainVolume']), **options)
        self.session.update(main_ended=False, started=time.monotonic(), retry_due=0, playing_since=0, last_position=None, progress_at=time.monotonic())
        if reset:
            self.session['attempts'] = 0

    def start_bg(self):
        station = self.stations.get(self.settings.get('bgStation'))
        if not self.voice_available() or not self.settings.get('mix') or not station or station['category'] in ('lofi', 'ambience', 'youtube'):
            return
        url = station['url']
        if station.get('kind') == 'podcast':
            # Fetch outside control.lock; an unavailable publisher must never
            # prevent the user from pausing or stopping the listening session.
            self.stop_channel('feed')
            token = str(time.time_ns())
            self.session['feed_token'] = token
            self.spawn_service('feed', [sys.executable, str(ROOT/'lofi-player'),
                                       '--resolve-feed', station['id'], token])
            return
        self.spawn('bg', url, self.effective(self.settings['bgVolume']), paused=self.session['mode'] == 'paused',
                   fade_in=True)

    def start_nature(self, id):
        entry = self.settings['natureLayers'].get(id, {})
        if not entry.get('enabled'):
            return
        volume = level(entry.get('volume', 25))
        self.spawn('nature-' + id, ROOT/self.stations[id]['url'], self.effective(volume),
                   loop=True, paused=self.session['mode'] == 'paused', fade_in=True)

    def ensure_services(self):
        if self.session['mode'] == 'stopped':
            return
        # Retire a worker that still has pre-update controller code in memory.
        if self.alive('volume'):
            pid = int((self.runtime/'volume.pid').read_text())
            if WORKER_VERSION.encode() not in Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0'):
                self.stop_channel('volume')
        if not self.alive('volume'):
            self.spawn_service('volume', [sys.executable, str(ROOT/'lofi-player'), '--watch', WORKER_VERSION])
        if not self.alive('mpris'):
            self.spawn_service('mpris', [sys.executable, str(ROOT/'lofi-mpris'), str(ROOT/'lofi-player')])

    def spawn_service(self, channel, args):
        with (self.runtime/'logs'/f'{channel}.log').open('ab') as log:
            child = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        (self.runtime/f'{channel}.pid').write_text(str(child.pid) + '\n')

    def begin(self, station=None):
        self.remember_youtube(force=True)
        previous = self.session['mode']
        if previous == 'paused' and self.is_youtube():
            self.session['started'] = time.monotonic()
        self.session['mode'] = 'playing'
        self.session['pending'] = None
        self.session['progress_at'] = time.monotonic()
        if station is not None:
            self.require_station(station, 'lofi')
            self.settings['defaultStation'] = station
            self.session['station'] = station
        if station or previous == 'stopped' or self.session.get('main_ended') or not self.alive('main'):
            self.start_music()
        else:
            # Resuming: the stream is still loaded and silent after its fade
            # out, so unpause it and glide back to level.
            self.fade_in_channel('main', self.fade_in_seconds())
        if not self.voice_available():
            self.session['feed_token'] = ''
            self.stop_channel('feed')
            self.stop_channel('bg')
        elif not self.alive('bg') and not self.alive('feed'):
            self.start_bg()
        else:
            self.fade_in_channel('bg', self.fade_in_seconds())
        for id in self.nature:
            if not self.alive('nature-' + id):
                self.start_nature(id)
            else:
                entry = self.settings['natureLayers'].get(id, {})
                if entry.get('enabled'):
                    self.fade_in_channel('nature-' + id, self.fade_in_seconds())
        for channel in self.channels():
            if self.alive(channel):
                ipc(self.sock(channel), ['set_property', 'pause', False])
        (self.runtime/'paused.flag').unlink(missing_ok=True)

    def fade_configured(self):
        return self.settings.get('fadeEnabled', True) and self.fade_in_seconds() > 0

    def pause(self):
        self.remember_youtube(force=True)
        if self.session['mode'] == 'stopped':
            return
        if not self.fade_configured():
            # Fades off: pause immediately, exactly as before.
            self.session.update(mode='paused', retry_due=0, pending=None)
            for channel in self.channels(include_legacy=True):
                if self.alive(channel):
                    ipc(self.sock(channel), ['set_property', 'pause', True])
            (self.runtime/'paused.flag').touch()
            return
        # The UI reflects the pause at once; the audio ramps down and the
        # worker commits the hard pause when the ramp reaches silence.
        self.session.update(mode='paused', retry_due=0,
                            pending=dict(action='pause', at=time.monotonic() + self.fade_out_seconds()))
        self.fade_out_all(self.fade_out_seconds())
        self.commit_without_worker()

    def stop(self):
        self.remember_youtube(force=True)
        if not self.fade_configured():
            self.session.update(mode='stopped', retry_due=0, attempts=0, playing_since=0, feed_token='', pending=None)
            for channel in self.channels(include_legacy=True) + ['feed', 'volume', 'mpris']:
                self.stop_channel(channel)
            self.clear_feed_cache()
            (self.runtime/'paused.flag').unlink(missing_ok=True)
            return
        # Same shape as pause: stop intent is immediate, the processes are torn
        # down only after they have faded out.
        self.session.update(mode='stopped', retry_due=0, attempts=0, playing_since=0, feed_token='',
                            pending=dict(action='stop', at=time.monotonic() + self.fade_out_seconds()))
        self.fade_out_all(self.fade_out_seconds())
        self.commit_without_worker()

    def commit_without_worker(self):
        """If no volume worker is alive to run the ramp, finish the transport now.

        Called from control commands (a different process than the worker), so
        tearing the worker down here is safe."""
        if self.alive('volume'):
            return
        pending = self.session.get('pending') or {}
        if pending.get('action') == 'pause':
            for channel in self.channels(include_legacy=True):
                if self.alive(channel):
                    ipc(self.sock(channel), ['set_property', 'pause', True])
            (self.runtime/'paused.flag').touch()
        else:
            for channel in self.channels(include_legacy=True) + ['feed', 'volume', 'mpris']:
                self.stop_channel(channel)
            self.clear_feed_cache()
            (self.runtime/'paused.flag').unlink(missing_ok=True)
        self.session['pending'] = None

    def commit_pending(self):
        """Finish a transport that had to wait for its fade-out to complete."""
        pending = self.session.get('pending')
        if not pending or time.monotonic() < pending.get('at', 0):
            return
        action = pending.get('action')
        self.session['pending'] = None
        if action == 'pause':
            for channel in self.channels(include_legacy=True):
                if self.alive(channel):
                    ipc(self.sock(channel), ['set_property', 'pause', True])
            (self.runtime/'paused.flag').touch()
        elif action == 'stop':
            # Never signal the volume worker from here: this runs inside it, so
            # it tears everything else down and cleans up its own files as it
            # exits the watch loop.
            for channel in self.channels(include_legacy=True) + ['feed', 'mpris']:
                self.stop_channel(channel)
            self.clear_feed_cache()
            (self.runtime/'paused.flag').unlink(missing_ok=True)

    def clear_feed_cache(self):
        """A stopped session leaves no resolved podcast playlists behind."""
        for id in self.stations:
            cache = self.runtime/(hashlib.sha256(id.encode()).hexdigest()[:16] + '.m3u')
            cache.unlink(missing_ok=True)
            cache.with_suffix('.lock').unlink(missing_ok=True)

    def require_station(self, id, category):
        if id not in self.stations or self.stations[id]['category'] not in (('lofi', 'youtube') if category == 'lofi' else (category,)):
            raise ValueError(f'Unknown {category} station: {id}')

    def maintain(self):
        now = time.monotonic()
        # Finish a Pause/Stop as soon as its fade-out has had time to complete.
        self.commit_pending()
        # Migrate the single old nature process without resetting music/voice.
        if self.alive('noise'):
            self.stop_channel('noise')
            if self.session['mode'] != 'stopped':
                for id in self.nature:
                    self.start_nature(id)
        if self.session['mode'] != 'playing':
            return
        alive = self.alive('main')
        if self.is_youtube():
            self.remember_youtube()
            if alive and ipc(self.sock('main'), ['get_property', 'eof-reached']) is True:
                self.remember_youtube(force=True)
                self.session.update(main_ended=True, retry_due=0)
                return
            # Extraction can take longer than radio connection. Keep controls
            # responsive, but stop a stuck extractor instead of retrying forever.
            if alive and fetch_number(self.sock('main'), 'time-pos') is None:
                if now - self.session.get('started', now) < 45:
                    return
                self.stop_channel('main')
                alive = False
            if not alive:
                self.session.update(attempts=len(RETRY_DELAYS), retry_due=0)
                return
        position = ipc(self.sock('main'), ['get_property', 'time-pos']) if alive else None
        if isinstance(position, (int, float)):
            # Detect stalls even if mpv remains alive with an exhausted buffer.
            if position != self.session.get('last_position'):
                self.session.update(last_position=position, progress_at=now)
            if not self.session.get('playing_since'):
                self.session['playing_since'] = now
            if now - self.session.get('progress_at', now) < CONNECT_TIMEOUT:
                if now - self.session['playing_since'] >= STABLE_SECONDS:
                    self.session['attempts'] = 0
                self.session['retry_due'] = 0
                return
        elif alive and now - self.session.get('started', now) < CONNECT_TIMEOUT:
            return
        if alive:
            self.stop_channel('main')
        attempts = self.session.get('attempts', 0)
        if attempts >= len(RETRY_DELAYS):
            self.session['retry_due'] = 0
            return
        if not self.session.get('retry_due'):
            self.session['retry_due'] = now + RETRY_DELAYS[attempts]
        elif now >= self.session['retry_due']:
            self.session['attempts'] = attempts + 1
            self.start_music(reset=False)

    def status(self):
        main_alive = self.alive('main')
        mode = self.session['mode']
        position = ipc(self.sock('main'), ['get_property', 'time-pos']) if main_alive else None
        ready = isinstance(position, (int, float))
        live = self.is_youtube() and str(ipc(self.sock('main'), ['get_property', 'metadata/by-key/ytdl_is_live'])).lower() in ('true', 'yes', '1')
        retry_in = max(0, math.ceil(self.session.get('retry_due', 0) - time.monotonic()))
        if mode == 'stopped':
            main_state = 'stopped'
        elif mode == 'paused':
            main_state = 'paused'
        elif self.session.get('main_ended'):
            main_state = 'ended'
        elif ready:
            main_state = 'playing'
        elif main_alive:
            main_state = 'connecting' if not self.session.get('attempts') else 'reconnecting'
        elif self.session.get('attempts', 0) >= len(RETRY_DELAYS):
            main_state = 'failed'
        else:
            main_state = 'reconnecting'
        id = self.session.get('station', self.settings['defaultStation'])
        station = self.stations.get(id, dict(name='No sources available', category='', category_name='', url=''))
        bg = self.stations.get(self.settings.get('bgStation'), {})
        layers = []
        for sound in self.nature:
            config = self.settings['natureLayers'].get(sound, {})
            layers.append(dict(id=sound, name=self.stations[sound]['name'],
                               enabled=bool(config.get('enabled')), volume=level(config.get('volume', 25)),
                               running=self.alive('nature-' + sound)))
        selected = [s['id'] for s in layers if s['enabled']]
        state = dict(running=mode != 'stopped', paused=mode == 'paused', main_running=main_alive,
                     main_state=main_state, retry_in=retry_in, retry_attempt=self.session.get('attempts', 0),
                     station=id, name=station['name'], category='youtube' if self.is_youtube() else station['category'],
                     category_name='YouTube live' if station.get('kind') == 'youtube' else station['category_name'], url=station['url'],
                     main_volume=self.settings['mainVolume'], bg_volume=self.settings['bgVolume'],
                     master_volume=self.settings['masterVolume'], ducking=self.settings['ducking'],
                     bg_station=bg.get('id', ''), bg_name=bg.get('name', ''), bg_running=self.alive('bg'),
                     voice_available=self.voice_available(),
                     mix=self.settings.get('mix', False) and self.voice_available(), nature_layers=layers,
                     youtube_entries=self.settings.get('youtube', []), youtube_available=bool(shutil.which('yt-dlp')),
                     nature_volume=self.settings['natureVolume'], noise_volume=self.settings['natureVolume'],
                     noise_station=selected[0] if selected else 'off', noise_running=any(s['running'] for s in layers),
                     animations=bool(self.settings.get('animations', True)),
                     reveal_animations=bool(self.settings.get('revealAnimations', True)),
                     steam_animation=bool(self.settings.get('steamAnimation', True)),
                     glow_animation=bool(self.settings.get('glowAnimation', True)),
                     equalizer_animation=bool(self.settings.get('equalizerAnimation', True)),
                     fade_enabled=bool(self.settings.get('fadeEnabled', True)),
                     fade_seconds=level(self.settings.get('fadeSeconds', 3), 3),
                     reveal_speed=level(self.settings.get('revealSpeed', 1), 1),
                     collapsible_sections=bool(self.settings.get('collapsibleSections', True)),
                     duck_level=level(self.settings.get('duckLevel', 35), 35),
                     index=self.music.index(id) if id in self.music else 0, count=len(self.music),
                     main_title=ipc(self.sock('main'), ['get_property', 'media-title']) if ready else '',
                     bg_title=ipc(self.sock('bg'), ['get_property', 'media-title']) if self.alive('bg') else '',
                     # Progress is only meaningful when the stream reports a
                     # duration; live radio leaves it null, podcasts do not.
                     main_position=fetch_number(self.sock('main'), 'time-pos') if ready else None,
                     main_duration=fetch_number(self.sock('main'), 'duration') if ready and not live else None,
                     bg_position=fetch_number(self.sock('bg'), 'time-pos') if self.alive('bg') else None,
                     bg_duration=fetch_number(self.sock('bg'), 'duration') if self.alive('bg') else None)
        write_json(self.runtime/'status.json', state)
        return state

    def action(self, command, args):
        if command in ('play', 'resume', 'pause', 'toggle', 'stop', 'start', 'station', 'next', 'skip', 'prev', 'previous'):
            try:
                parent = Path(f'/proc/{os.getppid()}/comm').read_text().strip()
            except OSError:
                parent = 'unknown'
            log_control(self.runtime, dict(command=command, source=os.environ.get('LOFI_CONTROL_SOURCE', parent),
                                           before=self.session['mode']))
        if command in ('start', 'station'):
            self.require_station(args[0], 'lofi')
            self.begin(args[0])
        elif command in ('play', 'resume'):
            self.begin(args[0] if args else None)
        elif command == 'toggle':
            self.pause() if self.session['mode'] == 'playing' and not self.session.get('main_ended') else self.begin()
        elif command == 'pause':
            self.pause()
        elif command == 'stop':
            self.stop()
        elif command in ('next', 'skip', 'prev', 'previous'):
            current = self.session.get('station', self.settings['defaultStation'])
            index = self.music.index(current) if current in self.music else 0
            if not self.music:
                raise ValueError('No sources available')
            self.begin(self.music[(index + (1 if command in ('next', 'skip') else -1)) % len(self.music)])
        elif command in ('vol', 'volume'):
            channel, value = args
            value = int(value)
            if not 0 <= value <= 100:
                raise ValueError('Volume must be 0-100')
            keys = {'main': 'mainVolume', 'bg': 'bgVolume', 'master': 'masterVolume',
                    'nature': 'natureVolume', 'noise': 'natureVolume'}
            if channel in ('nature', 'noise'):
                # Legacy CLI shortcut: set each selected sound to this direct level.
                for layer in self.settings['natureLayers'].values():
                    if layer.get('enabled'):
                        layer['volume'] = value
            elif channel in keys:
                self.settings[keys[channel]] = value
            else:
                self.require_station(channel, 'ambience')
                self.settings['natureLayers'].setdefault(channel, {'enabled': False})['volume'] = value
        elif command in ('bg', 'background'):
            id = args[0]
            if id != 'off' and (id not in self.stations or self.stations[id]['category'] in ('lofi', 'ambience', 'youtube')):
                raise ValueError('Unknown voice station')
            self.settings.update(bgStation='' if id == 'off' else id, mix=id != 'off')
            self.session['feed_token'] = ''
            self.stop_channel('feed')
            self.stop_channel('bg')
            if self.session['mode'] != 'stopped':
                self.start_bg()
        elif command == 'mix':
            value = args[0] if args else 'toggle'
            if value not in ('on', 'off', 'true', 'false', 'toggle'):
                raise ValueError('mix takes on/off/toggle')
            self.settings['mix'] = not self.settings.get('mix') if value == 'toggle' else value in ('on', 'true')
            if self.settings['mix'] and self.session['mode'] != 'stopped':
                self.start_bg()
            else:
                self.session['feed_token'] = ''
                self.stop_channel('feed')
                self.stop_channel('bg')
        elif command == 'nature':
            id, choice = args
            self.require_station(id, 'ambience')
            if choice not in ('on', 'off', 'toggle'):
                raise ValueError('nature takes on/off/toggle')
            layer = self.settings['natureLayers'].setdefault(id, {'volume': 25, 'enabled': False})
            layer['enabled'] = not layer['enabled'] if choice == 'toggle' else choice == 'on'
            if layer['enabled'] and self.session['mode'] != 'stopped':
                if not self.alive('nature-' + id):
                    self.start_nature(id)
            else:
                self.stop_channel('nature-' + id)
        elif command == 'noise':
            # Compatibility for saved scripts: replace the entire nature selection.
            id = args[0]
            if id != 'off':
                self.require_station(id, 'ambience')
            for sound in self.nature:
                self.settings['natureLayers'].setdefault(sound, {'volume': 25})['enabled'] = sound == id
                self.stop_channel('nature-' + sound)
            if id != 'off' and self.session['mode'] != 'stopped':
                self.start_nature(id)
        elif command == 'youtube-add':
            if not 1 <= len(args) <= 2:
                raise ValueError('Paste a YouTube link and an optional title.')
            url = canonical_url(args[0])
            identity = 'youtube-' + url.rsplit('=', 1)[1]
            existing = next((e for e in self.settings['youtube'] if e['id'] == identity), None)
            title = clean_title(args[1]) if len(args) == 2 else ''
            if existing:
                if title:
                    existing['name'] = title
            else:
                if len(self.settings['youtube']) >= MAX_SAVED:
                    raise ValueError('Your library is full (40 videos). Remove one before adding another.')
                self.settings['youtube'].append(dict(id=identity, url=url,
                    name=title or 'YouTube · ' + url.rsplit('=', 1)[1], position=0))
            self.add_saved_sources()
        elif command == 'youtube-remove':
            identity, = args
            if not any(e['id'] == identity for e in self.settings['youtube']):
                raise ValueError('This saved video no longer exists.')
            if self.session['station'] == identity:
                self.remember_youtube(force=True)
                self.stop_channel('main')
                radio = next(s for s in self.music if self.stations[s]['category'] == 'lofi')
                # Removing a playing item must not unexpectedly start the radio.
                self.session.update(station=radio, mode='paused', pending=None, main_ended=False, retry_due=0)
                self.pause()
            if self.settings['defaultStation'] == identity:
                self.settings['defaultStation'] = next(s for s in self.music if self.stations[s]['category'] == 'lofi')
            self.settings['youtube'] = [e for e in self.settings['youtube'] if e['id'] != identity]
            self.stations.pop(identity, None)
            self.music = [s for s in self.music if s != identity]
        elif command == 'seek':
            value, = args
            seconds = float(value)
            duration = fetch_number(self.sock('main'), 'duration')
            if not math.isfinite(seconds) or duration is None or duration <= 0 or not self.alive('main'):
                raise ValueError('Seeking is available once a video is playing.')
            ipc(self.sock('main'), ['seek', max(0, min(duration - .1, seconds)), 'absolute'])
            if self.session.get('main_ended') and self.session['mode'] == 'playing':
                ipc(self.sock('main'), ['set_property', 'pause', False])
            self.session.update(main_ended=False, progress_at=time.monotonic())
            self.remember_youtube(force=True)
        elif command == 'ducking':
            if args[0] not in ('on', 'off'):
                raise ValueError('ducking takes on/off')
            self.settings['ducking'] = args[0] == 'on'
        elif command == 'ui':
            # Persist a look-and-feel preference. Keys are the setting names the
            # panel uses; booleans take on/off, numbers take 0-8 (fade seconds)
            # or 0-3 (reveal speed).
            key, value = args
            boolean_keys = {'animations': 'animations', 'reveal': 'revealAnimations',
                            'steam': 'steamAnimation', 'glow': 'glowAnimation',
                            'equalizer': 'equalizerAnimation', 'fade': 'fadeEnabled',
                            'collapsible': 'collapsibleSections'}
            number_keys = {'fadeSeconds': 8, 'revealSpeed': 3, 'duckLevel': 100}
            if key in boolean_keys:
                if value not in ('on', 'off'):
                    raise ValueError(f'{key} takes on/off')
                self.settings[boolean_keys[key]] = value == 'on'
            elif key in number_keys:
                number = int(value)
                if not 0 <= number <= number_keys[key]:
                    raise ValueError(f'{key} takes 0-{number_keys[key]}')
                self.settings[key] = number
            else:
                raise ValueError('Unknown ui setting')
        elif command == 'default':
            self.require_station(args[0], 'lofi')
            self.settings['defaultStation'] = args[0]
            if self.session['mode'] == 'stopped':
                self.session['station'] = args[0]
        elif command == 'bridge-restart':
            self.stop_channel('mpris')
        elif command != 'status':
            raise ValueError('Unknown command')
        self.save()
        self.ensure_services()
        # The persistent worker owns smoothing; fresh CLI instances must not
        # reset its duck gain on every status read or slider adjustment.
        if not self.alive('volume'):
            self.ducker.poll(gains=self.step_fades())
        return self.status()


def watch(player):
    with (player.runtime/'volume-worker.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        deadline = 0
        try:
            while True:
                # Compose transport gain with current mix and dictation gain.
                fading = player.step_fades()
                player.ducker.poll(gains=fading)
                if time.monotonic() >= deadline and player.acquire(blocking=False):
                    try:
                        if player.session['mode'] == 'stopped' and not player.session.get('pending'):
                            # Retire this worker: remove its pid marker so a later
                            # Play starts a fresh one. Reap first, so a runtime
                            # directory that vanished with its PID files cannot
                            # leave detached audio behind.
                            player.reap_orphans()
                            (player.runtime/'volume.pid').unlink(missing_ok=True)
                            return
                        player.maintain()
                        player.save()
                        player.status()
                    finally:
                        player.release()
                    deadline = time.monotonic() + 1
                    # Reap mpv children from previous attempts in this worker.
                    try:
                        while os.waitpid(-1, os.WNOHANG)[0]:
                            pass
                    except ChildProcessError:
                        pass
                time.sleep(.1)
        except BaseException:
            # A worker that dies must not leave detached audio behind. Only
            # orphans are reaped, so healthy playback survives a transient
            # fault while a removed runtime directory is still cleaned up.
            try:
                player.reap_orphans(orphan_only=True)
            except Exception:
                pass
            raise


def resolve_feed(player, id, token):
    station = player.stations[id]
    cache = player.runtime/(hashlib.sha256(id.encode()).hexdigest()[:16] + '.m3u')
    with cache.with_suffix('.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # This resolver is already a dedicated process. Fetch in it directly,
        # so cancellation needs only its pinned pidfd, never killpg().
        signal.alarm(12)
        try:
            resolve_playlist(station['url'], cache)
        finally:
            signal.alarm(0)
    player.acquire()
    try:
        if (player.session['mode'] != 'stopped' and player.voice_available() and player.settings.get('mix')
                and player.settings.get('bgStation') == id and player.session.get('feed_token') == token):
            player.spawn('bg', cache, player.effective(player.settings['bgVolume']),
                         paused=player.session['mode'] == 'paused')
            player.session['feed_token'] = ''
            player.save()
            player.status()
    finally:
        player.release()


def main():
    player = Player()
    try:
        if sys.argv[1:2] == ['--resolve-feed']:
            resolve_feed(player, *sys.argv[2:])
        elif sys.argv[1:2] == ['--watch']:
            watch(player)
        else:
            player.acquire()
            try:
                command = sys.argv[1] if len(sys.argv) > 1 else 'status'
                state = player.action(command, sys.argv[2:])
                if command == 'status':
                    print(json.dumps(state, ensure_ascii=False))
            finally:
                player.release()
    except (ValueError, IndexError, OSError, subprocess.TimeoutExpired) as error:
        print(f'Lofi Focus: {error}', file=sys.stderr)
        sys.exit(1)
