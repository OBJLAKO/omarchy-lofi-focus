"""Integration tests with real mpv IPC, silent local audio and an isolated D-Bus."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
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
            for st in cat['stations']:
                st['url'] = str(wav); st.pop('kind', None)
        (self.plugin / 'stations.json').write_text(json.dumps(catalog))
        runtime = self.base / 'runtime'; runtime.mkdir()
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(self.base/'state'), PATH=str(self.bin)+':'+os.environ['PATH'])
        self.before = {p.name: p.read_bytes() for p in self.plugin.iterdir() if p.is_file()}

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
        after={p.name:p.read_bytes() for p in self.plugin.iterdir() if p.is_file()}
        self.assertEqual(self.before,after,'Playback must never modify watched plugin files')

    def test_concurrent_updates(self):
        jobs=[subprocess.Popen([str(self.plugin/'lofi-player'),'vol',channel,value],env=self.env,stdout=subprocess.DEVNULL) for channel,value in [('main','43'),('bg','17')]]
        for job in jobs: self.assertEqual(job.wait(timeout=20),0)
        st=self.status();self.assertEqual(st['main_volume'],43);self.assertEqual(st['bg_volume'],17)

if __name__=='__main__': unittest.main()
