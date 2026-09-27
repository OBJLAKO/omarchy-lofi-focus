"""Regression coverage for fade ownership, mute and transport completion."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lofi_backend as backend


class FadeTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        env = mock.patch.dict(os.environ, XDG_RUNTIME_DIR=str(self.base/'runtime'),
                              XDG_STATE_HOME=str(self.base/'state'))
        env.start(); self.addCleanup(env.stop)
        self.player = backend.Player()
        self.addCleanup(self.player.lock.close)
        self.addCleanup(self.player.fades_lock.close)
        self.player.acquire(); self.addCleanup(self.player.release)
        self.player.alive = mock.Mock(return_value=True)
        self.now = 100.0
        clock = mock.patch.object(backend.time, 'monotonic', side_effect=lambda: self.now)
        clock.start(); self.addCleanup(clock.stop)

    def test_completed_pause_holds_silence_until_transport_commits(self):
        with mock.patch.object(backend, 'ipc', return_value=65):
            self.player.request_fade('main', 1, silence=True)
        self.now += 1.1
        self.assertEqual(self.player.step_fades()['main'], 0)
        self.now += 2
        self.assertEqual(self.player.step_fades()['main'], 0)

    def test_start_muted_can_be_unmuted_after_fade(self):
        self.player.settings['masterVolume'] = 0
        with mock.patch.object(backend, 'ipc', return_value=0):
            self.player.request_fade('main', 1)
        self.now += 2
        self.assertEqual(self.player.step_fades()['main'], 1)
        self.assertNotIn('main', self.player.step_fades())

    def test_completed_fade_does_not_restore_cached_old_volume(self):
        with mock.patch.object(backend, 'ipc', return_value=0):
            self.player.request_fade('main', 1)
        self.now += .5
        self.assertAlmostEqual(self.player.step_fades()['main'], .5)
        self.player.settings['mainVolume'] = 20
        self.now += .6
        self.assertEqual(self.player.step_fades()['main'], 1)
        self.assertNotIn('main', self.player.step_fades())

    def test_resume_with_fades_disabled_releases_silent_hold(self):
        with mock.patch.object(backend, 'ipc', return_value=0):
            self.player.request_fade('main', 1, silence=True)
            self.player.settings['fadeEnabled'] = False
            self.player.request_fade('main', 1)
        self.assertEqual(self.player.step_fades()['main'], 1)

    def test_corrupt_or_old_fade_is_discarded(self):
        backend.write_json(self.player.fades_path, {'main': {'to': 65}, 'bg': None})
        self.assertEqual(self.player.step_fades(), {})


class StorageTest(unittest.TestCase):
    def test_existing_temporary_symlink_is_not_followed(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            victim = base/'other'; victim.write_text('untouched')
            path = base/'settings.json'
            path.with_suffix('.json.tmp').symlink_to(victim)
            backend.write_json(path, {'volume': 20})
            self.assertEqual(victim.read_text(), 'untouched')
            self.assertEqual(json.loads(path.read_text()), {'volume': 20})

    def test_failed_save_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(OSError):
                backend.write_json(Path(directory)/'missing/settings.json', {})
