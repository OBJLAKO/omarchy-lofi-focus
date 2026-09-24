"""Dictation auto-pause must not override the focus mix or manual media keys."""
from pathlib import Path
import sys
import unittest
from unittest import mock
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lofi_media import DictationTransport, is_voxtype_process


class DictationTransportTest(unittest.TestCase):
    def test_dictation_pause_and_resume_leave_playback_unchanged(self):
        policy = DictationTransport()
        self.assertTrue(policy.ignore('Pause', 42, True, True))
        self.assertTrue(policy.ignore('Play', 42, True, True))
        self.assertFalse(policy.ignore('Stop', 42, True, True))

    def test_manual_controls_still_work_during_dictation(self):
        policy = DictationTransport()
        policy.ignore('Pause', 42, True, True)
        for method in ('Pause', 'Play', 'PlayPause', 'Stop'):
            self.assertFalse(policy.ignore(method, 99, False, True))
        # A manual Stop must not be undone by VoxType's later Play, even if
        # the user turned ducking off in the meantime.
        self.assertTrue(policy.ignore('Play', 42, True, False))
        self.assertFalse(policy.ignore('Play', 42, True, False))

    def test_ducking_disabled_preserves_voxtype_media_control(self):
        policy = DictationTransport()
        self.assertFalse(policy.ignore('Pause', 42, True, False))
        self.assertFalse(policy.ignore('Play', 42, True, False))
        self.assertFalse(policy.ignore('Pause', None, True, True))

    def test_voxtype_symlink_variant_and_other_executable(self):
        with mock.patch('lofi_media.shutil.which', return_value='/usr/bin/voxtype'):
            with mock.patch.object(Path, 'resolve', return_value=Path('/usr/lib/voxtype/voxtype-vulkan')):
                self.assertTrue(is_voxtype_process(42))
            with mock.patch.object(Path, 'resolve', side_effect=[Path('/usr/bin/playerctl'), Path('/usr/lib/voxtype/voxtype-vulkan')]):
                self.assertFalse(is_voxtype_process(99))
            with mock.patch.object(Path, 'resolve', side_effect=OSError('gone')):
                self.assertFalse(is_voxtype_process(42))

if __name__ == '__main__':
    unittest.main()
