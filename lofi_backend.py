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
import select
import socket
import subprocess
import sys
import time

from lofi_duck import Ducker
from lofi_feed import resolve as resolve_playlist

ROOT = Path(__file__).resolve().parent
WORKER_VERSION = hashlib.sha256(Path(__file__).read_bytes() + (ROOT/'lofi_duck.py').read_bytes()).hexdigest()
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


def read_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return fallback


def write_json(path, value):
    text = json.dumps(value, indent=2) + '\n'
    try:
        if path.read_text() == text:
            return
    except OSError:
        pass
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(text)
    temporary.replace(path)


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


def level(value, default=0):
    try:
        number = float(value)
        return max(0, min(100, number)) if math.isfinite(number) else default
    except (TypeError, ValueError):
        return default


def ipc(path, command):
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(.15)
            client.connect(str(path))
            client.sendall((json.dumps({'command': command, 'request_id': 1}) + '\n').encode())
            with client.makefile() as stream:
                for line in stream:
                    reply = json.loads(line)
                    if reply.get('request_id') == 1:
                        return reply.get('data') if reply.get('error') == 'success' else None
    except (OSError, ValueError):
        pass
    return None


class Player:
    def __init__(self):
        self.runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'sky.lofi'
        self.settings_dir = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state'))) / 'sky.lofi'
        self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.settings_dir.mkdir(parents=True, exist_ok=True)
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
        self.fades_revision = None

    def reload_catalog(self):
        catalog = read_json(ROOT/'stations.json', {})
        self.stations = {s['id']: dict(s, category=c['id'], category_name=c['name'])
                         for c in catalog.get('categories', []) for s in c['stations']}
        self.music = [s for s in self.stations if self.stations[s]['category'] == 'lofi']
        self.nature = [s for s in self.stations if self.stations[s]['category'] == 'ambience']

    def acquire(self, blocking=True):
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError:
            return False
        self.reload_catalog()
        self.settings = read_json(self.settings_dir/'settings.json', read_json(ROOT/'settings.json', {}))
        for key, value in dict(defaultStation='lofi-lilo', mainVolume=65, bgVolume=20,
                               bgStation='talk-bbc-world', mix=True, masterVolume=100, ducking=True).items():
            self.settings.setdefault(key, value)
        previous_default = self.settings['defaultStation']
        if previous_default not in self.music:
            self.settings['defaultStation'] = self.music[0]
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
        self.session = read_json(self.runtime/'session.json', {})
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
            return ('--input-ipc-server=' + str(self.sock(channel))).encode() in argv
        except OSError:
            return False

    def alive(self, channel):
        try:
            pid = int((self.runtime/f'{channel}.pid').read_text())
            return pid > 0 and self.matches_process(channel, pid)
        except (OSError, ValueError):
            return False

    def stop_channel(self, channel):
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
                        exited = select.poll()
                        exited.register(handle, select.POLLIN)
                        try:
                            signal.pidfd_send_signal(handle, signal.SIGTERM)
                            if not exited.poll(250):
                                signal.pidfd_send_signal(handle, signal.SIGKILL)
                                exited.poll(250)
                        except ProcessLookupError:
                            pass  # The pinned process exited; never follow a reused PID.
                finally:
                    os.close(handle)
        pid_path.unlink(missing_ok=True)
        self.sock(channel).unlink(missing_ok=True)

    def spawn(self, channel, url, volume, loop=False, paused=False, fade_in=False):
        self.stop_channel(channel)
        log = self.runtime/'logs'/f'{channel}.log'
        if log.exists():
            log.replace(log.with_suffix('.log.previous'))
        # A new stream starts silent and ramps up, so it glides in rather than
        # popping. The worker owns its volume until the ramp finishes.
        start_volume = 0 if (fade_in and not paused) else volume
        # Warnings/errors and lifecycle messages, not every IPC request.
        args = ['mpv', '--no-config', '--no-video', '--terminal=yes', '--input-terminal=no', '--load-scripts=no',
                '--ytdl=no', '--audio-display=no', '--msg-level=all=warn,cplayer=info',
                '--msg-color=no', '--term-status-msg=', '--network-timeout=12',
                f'--volume={start_volume}', f'--input-ipc-server={self.sock(channel)}',
                '--user-agent=sky.lofi/1.0 (mpv)']
        if loop:
            args.append('--loop-file=inf')
        if paused:
            args.append('--pause')
        with log.open('wb') as output:
            child = subprocess.Popen(args + [str(url)], stdin=subprocess.DEVNULL,
                                     stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        (self.runtime/f'{channel}.pid').write_text(str(child.pid) + '\n')
        for _ in range(30):
            if self.sock(channel).exists() or child.poll() is not None:
                break
            time.sleep(.01)
        if fade_in and not paused:
            self.request_fade(channel, volume, FADE_IN_SECONDS)

    def effective(self, base):
        return level(base) * level(self.settings['masterVolume'], 100) / 100 * (
            .2 if self.settings.get('ducking', True) and self.ducker.recording() else 1)

    def request_fade(self, channel, target, duration):
        """Queue a volume ramp for the worker. Reads current mpv volume as the start."""
        if not self.alive(channel):
            return
        current = ipc(self.sock(channel), ['get_property', 'volume'])
        start = float(current) if isinstance(current, (int, float)) else float(target)
        fcntl.flock(self.fades_lock, fcntl.LOCK_EX)
        try:
            self.fades = read_json(self.fades_path, {})
            if duration <= 0 or abs(start - float(target)) < 1:
                self.fades.pop(channel, None)
                ipc(self.sock(channel), ['set_property', 'volume', float(target)])
            else:
                self.fades[channel] = dict(from_=start, to=float(target),
                                           started=time.monotonic(), duration=float(duration))
            write_json(self.fades_path, self.fades)
        finally:
            fcntl.flock(self.fades_lock, fcntl.LOCK_UN)

    def fade_out_all(self, duration=FADE_OUT_SECONDS):
        for channel in self.channels(include_legacy=True):
            if self.alive(channel):
                self.request_fade(channel, 0.0, duration)

    def fade_in_channel(self, channel, target, duration=FADE_IN_SECONDS):
        if self.alive(channel):
            self.request_fade(channel, target, duration)

    def step_fades(self):
        """Advance every active ramp. Called by the volume worker each tick."""
        try:
            revision = self.fades_path.stat().st_mtime_ns
        except OSError:
            revision = None
        try:
            fcntl.flock(self.fades_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return set()  # A control command is rewriting the file; try next tick.
        try:
            if revision != self.fades_revision:
                self.fades = read_json(self.fades_path, {})
                self.fades_revision = revision
            if not self.fades:
                return set()
            now = time.monotonic()
            active = set()
            changed = False
            for channel, fade in list(self.fades.items()):
                if not self.alive(channel):
                    self.fades.pop(channel, None); changed = True
                    continue
                duration = float(fade.get('duration', 0)) or 1.0
                progress = min(1.0, (now - float(fade.get('started', now))) / duration)
                start = float(fade.get('from_', 0)); target = float(fade.get('to', 0))
                volume = start + (target - start) * ease(progress)
                ipc(self.sock(channel), ['set_property', 'volume', volume])
                if progress >= 1.0:
                    self.fades.pop(channel, None); changed = True
                else:
                    active.add(channel)
            if changed or self.fades:
                write_json(self.fades_path, self.fades)
                self.fades_revision = self.fades_path.stat().st_mtime_ns
            return active
        finally:
            fcntl.flock(self.fades_lock, fcntl.LOCK_UN)



    def start_music(self, reset=True):
        station = self.stations[self.session['station']]
        self.spawn('main', station['url'], self.effective(self.settings['mainVolume']), fade_in=True)
        self.session.update(started=time.monotonic(), retry_due=0, playing_since=0, last_position=None, progress_at=time.monotonic())
        if reset:
            self.session['attempts'] = 0

    def start_bg(self):
        station = self.stations.get(self.settings.get('bgStation'))
        if not self.settings.get('mix') or not station or station['category'] in ('lofi', 'ambience'):
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
        previous = self.session['mode']
        self.session['mode'] = 'playing'
        self.session['pending'] = None
        self.session['progress_at'] = time.monotonic()
        if station is not None:
            self.require_station(station, 'lofi')
            self.settings['defaultStation'] = station
            self.session['station'] = station
        if station or previous == 'stopped' or not self.alive('main'):
            self.start_music()
        else:
            # Resuming: the stream is still loaded and silent after its fade
            # out, so unpause it and glide back to level.
            self.fade_in_channel('main', self.effective(self.settings['mainVolume']))
        if not self.alive('bg') and not self.alive('feed'):
            self.start_bg()
        else:
            self.fade_in_channel('bg', self.effective(self.settings['bgVolume']))
        for id in self.nature:
            if not self.alive('nature-' + id):
                self.start_nature(id)
            else:
                entry = self.settings['natureLayers'].get(id, {})
                if entry.get('enabled'):
                    self.fade_in_channel('nature-' + id, self.effective(level(entry.get('volume', 25))))
        for channel in self.channels():
            if self.alive(channel):
                ipc(self.sock(channel), ['set_property', 'pause', False])
        (self.runtime/'paused.flag').unlink(missing_ok=True)

    def pause(self):
        if self.session['mode'] == 'stopped':
            return
        # The UI reflects the pause at once; the audio ramps down and the
        # worker commits the hard pause when the ramp reaches silence.
        self.session.update(mode='paused', retry_due=0,
                            pending=dict(action='pause', at=time.monotonic() + FADE_OUT_SECONDS))
        self.fade_out_all()
        self.commit_without_worker()

    def stop(self):
        # Same shape as pause: stop intent is immediate, the processes are torn
        # down only after they have faded out.
        self.session.update(mode='stopped', retry_due=0, attempts=0, playing_since=0, feed_token='',
                            pending=dict(action='stop', at=time.monotonic() + FADE_OUT_SECONDS))
        self.fade_out_all()
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
        if id not in self.stations or self.stations[id]['category'] != category:
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
        retry_in = max(0, math.ceil(self.session.get('retry_due', 0) - time.monotonic()))
        if mode == 'stopped':
            main_state = 'stopped'
        elif mode == 'paused':
            main_state = 'paused'
        elif ready:
            main_state = 'playing'
        elif main_alive:
            main_state = 'connecting' if not self.session.get('attempts') else 'reconnecting'
        elif self.session.get('attempts', 0) >= len(RETRY_DELAYS):
            main_state = 'failed'
        else:
            main_state = 'reconnecting'
        id = self.session.get('station', self.settings['defaultStation'])
        station = self.stations.get(id, self.stations[self.music[0]])
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
                     station=id, name=station['name'], category=station['category'],
                     category_name=station['category_name'], url=station['url'],
                     main_volume=self.settings['mainVolume'], bg_volume=self.settings['bgVolume'],
                     master_volume=self.settings['masterVolume'], ducking=self.settings['ducking'],
                     bg_station=bg.get('id', ''), bg_name=bg.get('name', ''), bg_running=self.alive('bg'),
                     mix=self.settings.get('mix', False), nature_layers=layers,
                     nature_volume=self.settings['natureVolume'], noise_volume=self.settings['natureVolume'],
                     noise_station=selected[0] if selected else 'off', noise_running=any(s['running'] for s in layers),
                     index=self.music.index(id) if id in self.music else 0, count=len(self.music),
                     main_title=ipc(self.sock('main'), ['get_property', 'media-title']) if ready else '',
                     bg_title=ipc(self.sock('bg'), ['get_property', 'media-title']) if self.alive('bg') else '')
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
            self.pause() if self.session['mode'] == 'playing' else self.begin()
        elif command == 'pause':
            self.pause()
        elif command == 'stop':
            self.stop()
        elif command in ('next', 'skip', 'prev', 'previous'):
            current = self.session.get('station', self.settings['defaultStation'])
            index = self.music.index(current) if current in self.music else 0
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
            if id != 'off' and (id not in self.stations or self.stations[id]['category'] in ('lofi', 'ambience')):
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
        elif command == 'ducking':
            if args[0] not in ('on', 'off'):
                raise ValueError('ducking takes on/off')
            self.settings['ducking'] = args[0] == 'on'
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
        # Apply volume without clobbering ramps that were just requested.
        self.ducker.poll(skip=set(self.fades))
        self.ensure_services()
        return self.status()


def watch(player):
    with (player.runtime/'volume-worker.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        deadline = 0
        while True:
            # Advance volume ramps first; they own their channels' volume and
            # tell the ducker to leave those channels alone this tick.
            fading = player.step_fades()
            player.ducker.poll(skip=fading)
            if time.monotonic() >= deadline and player.acquire(blocking=False):
                try:
                    if player.session['mode'] == 'stopped' and not player.session.get('pending'):
                        # Retire this worker: remove its pid marker so a later
                        # Play starts a fresh one.
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
        if (player.session['mode'] != 'stopped' and player.settings.get('mix')
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
                    print(json.dumps(state))
            finally:
                player.release()
    except (ValueError, IndexError, OSError, subprocess.TimeoutExpired) as error:
        print(f'Lofi Focus: {error}', file=sys.stderr)
        sys.exit(1)
