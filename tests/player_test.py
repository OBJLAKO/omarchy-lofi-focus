"""Integration tests with real mpv IPC, silent local audio and an isolated D-Bus."""
import json
import os
import select
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import unittest
import wave
from backend_fixture import SOURCE, prepare_backend


class PlaybackNotReady(Exception):
    """Audio IPC exists only after an asynchronous native spawn completes."""


class PlayerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.plugin = self.base / 'plugin'
        shutil.copytree(SOURCE, self.plugin, ignore=shutil.ignore_patterns('.git', '__pycache__', 'target', 'perf-results'))
        self.bin = self.base / 'bin'; self.bin.mkdir()
        (self.bin / 'mpv').write_text('#!/bin/sh\nexec /usr/bin/mpv --ao=null --loop-file=inf "$@"\n')
        (self.bin / 'mpv').chmod(0o755)
        wav = self.base / 'tone.wav'
        with wave.open(str(wav), 'wb') as f:
            f.setparams((1, 2, 8000, 0, 'NONE', 'not compressed'))
            f.writeframes(b'\x00\x00' * 8000)
        catalog = json.loads((self.plugin / 'stations.json').read_text())
        for cat in catalog['categories']:
            if cat['id'] == 'ambience':
                # Keep the historical nine-layer subprocess stress fixture.
                # The larger catalog and native mixer are verified separately.
                cat['stations'] = cat['stations'][:9]
                continue
            for st in cat['stations']:
                st['url'] = str(wav); st.pop('kind', None)
        (self.plugin / 'stations.json').write_text(json.dumps(catalog))
        runtime = self.base / 'runtime'; runtime.mkdir()
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(self.base/'state'), XDG_CONFIG_HOME=str(self.base/'config'), PATH=str(self.bin)+':'+os.environ['PATH'])
        self.backend = prepare_backend(self.plugin, self.env)
        self.before = {str(p.relative_to(self.plugin)): p.read_bytes() for p in self.plugin.rglob("*") if p.is_file()}

    def action(self, *args, check=True):
        result = subprocess.run([str(self.plugin/'lofi-player'), *args], env=self.env, capture_output=True, text=True, timeout=20)
        if check and result.returncode:
            error = subprocess.CalledProcessError(result.returncode, result.args, result.stdout, result.stderr)
            error.add_note('Backend stderr: ' + result.stderr)
            raise error
        return result

    def wait_for(self, predicate, timeout=6):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                if predicate():
                    return
            except PlaybackNotReady:
                pass
            time.sleep(.05)
        self.fail('Playback did not reach the expected state before the deadline')

    def wait_prop(self, channel, name, expected):
        self.wait_for(lambda: abs(self.prop(channel, name) - expected) < .1)

    def status(self): return json.loads(self.action('status').stdout)
    def channel(self, channel):
        if channel == 'noise':
            settings = json.loads((self.base/'state/sky.lofi/settings.json').read_text())
            return 'nature-' + next(k for k,v in settings['natureLayers'].items() if v['enabled'])
        return channel

    def pid(self, channel): return (self.base/'runtime/sky.lofi'/f'{self.channel(channel)}.pid').read_text()
    def prop(self, channel, name):
        path = self.base/'runtime/sky.lofi/sockets'/f'{self.channel(channel)}.sock'
        try:
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(.3)
                client.connect(str(path))
                client.sendall((json.dumps({'command':['get_property',name], 'request_id':73}) + '\n').encode())
                with client.makefile() as replies:
                    for _ in range(64):
                        raw = replies.readline(1024 * 1024 + 1)
                        if not raw or len(raw) > 1024 * 1024:
                            raise PlaybackNotReady('audio IPC disconnected')
                        reply = json.loads(raw)
                        if reply.get('request_id') == 73:
                            if reply.get('error') != 'success' or reply.get('data') is None:
                                raise PlaybackNotReady('audio property not decoded yet: ' + name)
                            return reply['data']
        except (FileNotFoundError, ConnectionRefusedError, TimeoutError) as error:
            raise PlaybackNotReady(str(error)) from error
        raise PlaybackNotReady('audio IPC returned no matching reply')

    def tearDown(self):
        self.action('ui', 'fade', 'off', check=False)
        self.action('stop', check=False)
        if self.backend == 'rust':
            # The reply acknowledges shutdown; the daemon still has a short
            # socket/lock cleanup tail. Pin its identity before waiting so a
            # temporary runtime is never removed underneath that final write.
            handle = None
            try:
                pid = int((self.base/'runtime/sky.lofi/controller.pid').read_text())
                handle = os.pidfd_open(pid)
            except (FileNotFoundError, ProcessLookupError):
                pass
            try:
                self.action('shutdown', check=False)
                if handle is not None:
                    self.assertTrue(select.select([handle], [], [], 3)[0], 'Controller did not finish shutdown')
            finally:
                if handle is not None:
                    os.close(handle)
        self.temp.cleanup()

    def test_lifecycle_and_settings(self):
        self.action('pause')
        self.action('play')
        self.assertTrue(self.status()['running'])
        main = self.pid('main'); bg = self.pid('bg')
        self.action('vol','main','37'); self.action('vol','bg','12')
        self.wait_prop('main', 'volume', 37)
        self.assertEqual(self.pid('main'),main)
        self.action('start','lofi-kalizo')
        self.assertEqual(self.pid('bg'),bg)
        self.action('pause')
        self.action('bg','voice-changelog')
        self.wait_for(lambda: self.prop('bg','pause'))
        self.action('resume'); self.assertFalse(self.prop('bg','pause'))
        self.assertNotEqual(self.action('bg','lofi-kalizo',check=False).returncode,0)
        self.assertNotEqual(self.action('start','talk-bbc-world',check=False).returncode,0)
        self.action('stop'); self.action('play')
        st=self.status(); self.assertEqual(st['station'],'lofi-kalizo'); self.assertEqual(st['main_volume'],37)
        self.action('bg','off'); self.assertFalse(self.status()['bg_running'])
        self.action('bg','off'); self.assertFalse(self.status()['bg_running'])
        after={str(p.relative_to(self.plugin)):p.read_bytes() for p in self.plugin.rglob("*") if p.is_file()}
        self.assertEqual(self.before,after,'Playback must never modify watched plugin files')

    def test_voxtype_ducking(self):
        vox = self.base/'runtime/voxtype'; vox.mkdir()
        (vox/'pid').write_text(str(os.getpid()))
        state = vox/'state'; state.write_text('idle')
        self.action('play')
        # Pin the duck level so the expected volumes are exact, then check it
        # is configurable below. Fades off keeps station switches immediate,
        # so this test measures ducking alone.
        self.action('ui', 'duckLevel', '20')
        self.action('ui', 'fade', 'off')
        def wait_volume(channel, expected):
            self.wait_for(lambda: abs(self.prop(channel, 'volume') - expected) < .1, timeout=3)
        state.write_text('recording')
        wait_volume('main', 13); wait_volume('bg', 4)
        self.assertEqual(self.status()['main_volume'], 65)
        self.action('vol', 'main', '40'); wait_volume('main', 8)
        self.action('start', 'lofi-kalizo'); wait_volume('main', 8)
        self.action('ducking', 'off'); wait_volume('main', 40)
        self.action('ducking', 'on'); wait_volume('main', 8)
        state.write_text('transcribing'); wait_volume('main', 40)
        state.write_text('recording'); wait_volume('main', 8)
        self.action('vol', 'master', '50'); wait_volume('main', 4); wait_volume('bg', 2)
        state.unlink(); wait_volume('main', 20); wait_volume('bg', 10)
        self.assertEqual(self.status()['main_volume'], 40)
        self.assertEqual(self.status()['bg_volume'], 20)
        self.action('vol', 'master', '0'); wait_volume('main', 0); wait_volume('bg', 0)
        self.action('vol', 'master', '100'); wait_volume('main', 40)
        # The ducked level is configurable: keeping 50% leaves the music
        # audible at half volume while recording.
        state.write_text('recording')
        self.action('ui', 'duckLevel', '50'); wait_volume('main', 20)
        self.action('ui', 'duckLevel', '0'); wait_volume('main', 0)
        state.unlink(); wait_volume('main', 40)
        self.action('pause'); self.action('resume'); wait_volume('main', 40)

    def test_ambience_and_missing_media_bridge(self):
        self.action('play')
        if self.backend == 'python':
            bridge = int(self.pid('mpris'))
            os.kill(bridge, 15)
        self.action('noise', 'noise-rain')
        self.action('vol', 'noise', '30')
        self.action('vol', 'master', '50')
        self.wait_prop('main', 'volume', 32.5)
        self.wait_prop('bg', 'volume', 10)
        self.wait_prop('noise', 'volume', 15)
        layers = {entry['id']: entry for entry in self.status()['nature_layers']}
        self.assertEqual(layers['noise-rain']['volume'], 30)
        noise = self.pid('noise')
        self.action('start', 'lofi-kalizo')
        self.assertEqual(self.pid('noise'), noise)
        self.action('pause'); self.wait_for(lambda: self.prop('noise', 'pause'))
        self.action('resume'); self.assertFalse(self.prop('noise', 'pause'))
        self.assertNotEqual(self.action('bg', 'noise-rain', check=False).returncode, 0)
        self.action('noise', 'off'); self.assertFalse(self.status()['noise_running'])
        self.action('noise', 'noise-wind'); self.action('stop'); self.action('play')
        self.assertTrue(self.status()['noise_running'])
        self.assertEqual(self.status()['noise_station'], 'noise-wind')
        # Killing the volume worker must not break the next master adjustment.
        if self.backend == 'python':
            worker = int(self.pid('volume')); os.kill(worker, 15); time.sleep(0.1)
        self.action('vol', 'master', '0')
        self.wait_prop('main', 'volume', 0)
        self.wait_prop('noise', 'volume', 0)
        if self.backend == 'python':
            self.assertNotEqual(self.pid('volume'), str(worker) + '\n')

    def test_existing_mpris_owner_does_not_disable_volume(self):
        owner = subprocess.Popen(['python3', str(self.plugin/'lofi-mpris'), '/bin/true'], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            time.sleep(0.4)
            self.action('play')
            self.action('ui', 'duckLevel', '20')
            self.action('vol', 'master', '25')
            self.wait_prop('main', 'volume', 16.25)
            vox = self.base/'runtime/voxtype'; vox.mkdir()
            (vox/'pid').write_text(str(os.getpid()))
            (vox/'state').write_text('recording')
            self.wait_prop('main', 'volume', 3.25)
        finally:
            owner.terminate(); owner.wait(timeout=3)

    def test_music_disconnect_keeps_background_controllable(self):
        self.action('play')
        self.action('noise', 'noise-rain')
        os.kill(int(self.pid('main')), 15)
        deadline = time.monotonic() + 3
        while self.status()['main_running'] and time.monotonic() < deadline:
            time.sleep(0.05)
        st = self.status()
        self.assertFalse(st['main_running'])
        self.assertTrue(st['running'])
        self.assertFalse(st['paused'])
        self.action('toggle')
        self.wait_for(lambda: self.status()['paused'])
        for channel in ('bg', 'noise'):
            self.wait_for(lambda channel=channel: self.prop(channel, 'pause'))
        self.action('toggle')
        for channel in ('bg', 'noise'):
            self.assertFalse(self.prop(channel, 'pause'))
        self.action('vol', 'master', '0')
        for channel in ('bg', 'noise'):
            self.wait_prop(channel, 'volume', 0)
        self.action('pause'); self.action('play')
        self.assertFalse(self.status()['paused'])
        self.action('start', 'lofi-lilo')
        self.assertTrue(self.status()['main_running'])
        self.action('stop')
        self.assertFalse(self.status()['running'])

    def test_nature_alone_can_pause_and_resume(self):
        self.action('play')
        self.action('noise', 'noise-rain')
        self.action('bg', 'off')
        os.kill(int(self.pid('main')), 15)
        time.sleep(0.1)
        self.assertTrue(self.status()['running'])
        self.action('pause')
        self.wait_for(lambda: self.prop('noise', 'pause'))
        self.assertTrue(self.status()['paused'])
        self.action('resume')
        self.assertFalse(self.prop('noise', 'pause'))
        self.action('stop')
        self.assertFalse(self.status()['running'])

    def test_mute_during_fade_is_immediate_and_stays_muted(self):
        self.action('ui', 'fadeSeconds', '8')
        self.action('play')
        self.action('vol', 'master', '0')
        self.wait_prop('main', 'volume', 0)
        time.sleep(.4)
        self.assertAlmostEqual(self.prop('main', 'volume'), 0)
        self.action('vol', 'master', '100')
        self.wait_for(lambda: self.prop('main', 'volume') > 0)

    def test_dictation_during_fade_still_ducks_audio(self):
        self.env['XDG_CONFIG_HOME'] = str(self.base/'config')
        vox = self.base/'runtime/voxtype'; vox.mkdir()
        (vox/'pid').write_text(str(os.getpid()))
        state = vox/'state'; state.write_text('idle')
        self.action('ui', 'fadeSeconds', '8')
        self.action('ui', 'duckLevel', '0')
        self.action('play')
        self.wait_for(lambda: self.prop('main', 'volume') > 1)
        state.write_text('recording')
        self.wait_prop('main', 'volume', 0)
        self.assertAlmostEqual(self.prop('bg', 'volume'), 0, places=1)

    def test_volume_after_completed_resume_uses_latest_mix(self):
        self.action('ui', 'fadeSeconds', '1')
        self.action('play')
        self.wait_prop('main', 'volume', 65)
        self.action('pause')
        self.wait_for(lambda: self.prop('main', 'pause'))
        self.action('resume')
        self.action('vol', 'main', '23')
        self.wait_prop('main', 'volume', 23)
        time.sleep(.4)
        self.assertAlmostEqual(self.prop('main', 'volume'), 23, places=1)

    def test_concurrent_updates(self):
        jobs=[subprocess.Popen([str(self.plugin/'lofi-player'),'vol',channel,value],env=self.env,stdout=subprocess.DEVNULL) for channel,value in [('main','43'),('bg','17')]]
        for job in jobs: self.assertEqual(job.wait(timeout=20),0)
        st=self.status();self.assertEqual(st['main_volume'],43);self.assertEqual(st['bg_volume'],17)

if __name__=='__main__': unittest.main()
