"""Integration tests with real mpv IPC, silent local audio and an isolated D-Bus."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import wave

SOURCE = Path(__file__).resolve().parents[1]

class PlayerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.plugin = self.base / 'plugin'
        shutil.copytree(SOURCE, self.plugin, ignore=shutil.ignore_patterns('.git', '__pycache__'))
        self.bin = self.base / 'bin'; self.bin.mkdir()
        (self.bin / 'mpv').write_text('#!/bin/sh\nexec /usr/bin/mpv --ao=null --loop-file=inf "$@"\n')
        (self.bin / 'mpv').chmod(0o755)
        wav = self.base / 'tone.wav'
        with wave.open(str(wav), 'wb') as f:
            f.setparams((1, 2, 8000, 0, 'NONE', 'not compressed'))
            f.writeframes(b'\x00\x00' * 8000)
        catalog = json.loads((self.plugin / 'stations.json').read_text())
        for cat in catalog['categories']:
            if cat['id'] == 'ambience': continue
            for st in cat['stations']:
                st['url'] = str(wav); st.pop('kind', None)
        (self.plugin / 'stations.json').write_text(json.dumps(catalog))
        runtime = self.base / 'runtime'; runtime.mkdir()
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(self.base/'state'), PATH=str(self.bin)+':'+os.environ['PATH'])
        self.before = {str(p.relative_to(self.plugin)): p.read_bytes() for p in self.plugin.rglob("*") if p.is_file()}

    def action(self, *args, check=True):
        return subprocess.run([str(self.plugin/'lofi-player'), *args], env=self.env, capture_output=True, text=True, timeout=20, check=check)

    def status(self): return json.loads(self.action('status').stdout)
    def pid(self, channel): return (self.base/'runtime/sky.lofi'/f'{channel}.pid').read_text()
    def prop(self, channel, name):
        out = subprocess.check_output([str(self.plugin/'lofi-ipc'),str(self.base/'runtime/sky.lofi/sockets'/f'{channel}.sock'),json.dumps({'command':['get_property',name]})],text=True)
        return json.loads(out)['data']

    def tearDown(self):
        self.action('stop', check=False)
        self.temp.cleanup()

    def test_lifecycle_and_settings(self):
        self.action('pause')
        self.action('play')
        self.assertTrue(self.status()['running'])
        main = self.pid('main'); bg = self.pid('bg')
        self.action('vol','main','37'); self.action('vol','bg','12')
        self.assertEqual(self.prop('main','volume'),37)
        self.assertEqual(self.pid('main'),main)
        self.action('start','lofi-fluid')
        self.assertEqual(self.pid('bg'),bg)
        self.action('pause'); self.action('bg','voice-changelog')
        self.assertTrue(self.prop('bg','pause'))
        self.action('resume'); self.assertFalse(self.prop('bg','pause'))
        self.assertNotEqual(self.action('bg','lofi-fluid',check=False).returncode,0)
        self.assertNotEqual(self.action('start','talk-bbc-world',check=False).returncode,0)
        self.action('stop'); self.action('play')
        st=self.status(); self.assertEqual(st['station'],'lofi-fluid'); self.assertEqual(st['main_volume'],37)
        self.action('bg','off'); self.assertFalse(self.status()['bg_running'])
        after={str(p.relative_to(self.plugin)):p.read_bytes() for p in self.plugin.rglob("*") if p.is_file()}
        self.assertEqual(self.before,after,'Playback must never modify watched plugin files')

    def test_voxtype_ducking(self):
        vox = self.base/'runtime/voxtype'; vox.mkdir()
        (vox/'pid').write_text(str(os.getpid()))
        state = vox/'state'; state.write_text('idle')
        self.action('play')
        def wait_volume(channel, expected):
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                if abs(self.prop(channel, 'volume') - expected) < 0.1: return
                time.sleep(0.05)
            self.assertAlmostEqual(self.prop(channel, 'volume'), expected, places=1)
        state.write_text('recording')
        wait_volume('main', 13); wait_volume('bg', 4)
        self.assertEqual(self.status()['main_volume'], 65)
        self.action('vol', 'main', '40'); wait_volume('main', 8)
        self.action('start', 'lofi-fluid'); wait_volume('main', 8)
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
        self.action('pause'); self.action('resume'); wait_volume('main', 40)

    def test_ambience_and_missing_media_bridge(self):
        self.action('play')
        bridge = int(self.pid('mpris'))
        os.kill(bridge, 15)
        self.action('noise', 'noise-rain')
        self.action('vol', 'noise', '30')
        self.action('vol', 'master', '50')
        self.assertAlmostEqual(self.prop('main', 'volume'), 32.5)
        self.assertAlmostEqual(self.prop('bg', 'volume'), 10)
        self.assertAlmostEqual(self.prop('noise', 'volume'), 15)
        noise = self.pid('noise')
        self.action('start', 'lofi-fluid')
        self.assertEqual(self.pid('noise'), noise)
        self.action('pause'); self.assertTrue(self.prop('noise', 'pause'))
        self.action('resume'); self.assertFalse(self.prop('noise', 'pause'))
        self.assertNotEqual(self.action('bg', 'noise-rain', check=False).returncode, 0)
        self.action('noise', 'off'); self.assertFalse(self.status()['noise_running'])
        self.action('noise', 'noise-wind'); self.action('stop'); self.action('play')
        self.assertTrue(self.status()['noise_running'])
        self.assertEqual(self.status()['noise_station'], 'noise-wind')
        # Killing the volume worker must not break the next master adjustment.
        worker = int(self.pid('volume')); os.kill(worker, 15); time.sleep(0.1)
        self.action('vol', 'master', '0')
        self.assertEqual(self.prop('main', 'volume'), 0)
        self.assertEqual(self.prop('noise', 'volume'), 0)
        self.assertNotEqual(self.pid('volume'), str(worker) + '\n')

    def test_existing_mpris_owner_does_not_disable_volume(self):
        owner = subprocess.Popen(['python3', str(self.plugin/'lofi-mpris'), '/bin/true'], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            time.sleep(0.4)
            self.action('play')
            self.action('vol', 'master', '25')
            self.assertAlmostEqual(self.prop('main', 'volume'), 16.25)
            vox = self.base/'runtime/voxtype'; vox.mkdir()
            (vox/'pid').write_text(str(os.getpid()))
            (vox/'state').write_text('recording')
            time.sleep(0.4)
            self.assertAlmostEqual(self.prop('main', 'volume'), 3.25)
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
        self.assertTrue(self.status()['paused'])
        for channel in ('bg', 'noise'):
            self.assertTrue(self.prop(channel, 'pause'))
        self.action('toggle')
        for channel in ('bg', 'noise'):
            self.assertFalse(self.prop(channel, 'pause'))
        self.action('vol', 'master', '0')
        for channel in ('bg', 'noise'):
            self.assertEqual(self.prop(channel, 'volume'), 0)
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
        self.assertTrue(self.prop('noise', 'pause'))
        self.assertTrue(self.status()['paused'])
        self.action('resume')
        self.assertFalse(self.prop('noise', 'pause'))
        self.action('stop')
        self.assertFalse(self.status()['running'])

    def test_concurrent_updates(self):
        jobs=[subprocess.Popen([str(self.plugin/'lofi-player'),'vol',channel,value],env=self.env,stdout=subprocess.DEVNULL) for channel,value in [('main','43'),('bg','17')]]
        for job in jobs: self.assertEqual(job.wait(timeout=20),0)
        st=self.status();self.assertEqual(st['main_volume'],43);self.assertEqual(st['bg_volume'],17)

if __name__=='__main__': unittest.main()
