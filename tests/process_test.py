"""Exercise pinned termination without relying on the kernel to reuse a PID."""
import errno
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lofi_backend as backend


class ProcessTerminationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.player = backend.Player.__new__(backend.Player)
        self.player.runtime = Path(self.temp.name)
        (self.player.runtime/'sockets').mkdir()
        self.pid_path = self.player.runtime/'main.pid'
        self.decoy = self.child()

    def child(self, target=False, stubborn=False):
        code = ('import signal,time; '
                + ('signal.signal(signal.SIGTERM,signal.SIG_IGN); ' if stubborn else '')
                + "print('ready',flush=True); time.sleep(30)")
        args = [sys.executable, '-c', code]
        if target:
            args.append('--input-ipc-server=' + str(self.player.sock('main')))
        child = subprocess.Popen(args, stdout=subprocess.PIPE, text=True)
        def cleanup():
            if child.poll() is None:
                child.kill()
            child.wait(timeout=3)
            child.stdout.close()
        self.addCleanup(cleanup)
        self.assertEqual(child.stdout.readline().strip(), 'ready')
        if target:
            self.pid_path.write_text(str(child.pid))
        return child

    def assert_decoy_alive(self):
        self.assertIsNone(self.decoy.poll(), 'Unrelated process was signalled')

    def test_normal_stop_signals_only_verified_process(self):
        target = self.child(target=True)
        self.player.stop_channel('main')
        self.assertEqual(target.wait(timeout=2), -signal.SIGTERM)
        self.assert_decoy_alive()
        self.assertFalse(self.pid_path.exists())

    def test_pid_file_replacement_after_identity_check_does_not_redirect_signal(self):
        target = self.child(target=True)
        matches = self.player.matches_process
        def replace(channel, pid):
            valid = matches(channel, pid)
            self.pid_path.write_text(str(self.decoy.pid))
            return valid
        with mock.patch.object(self.player, 'matches_process', side_effect=replace):
            self.player.stop_channel('main')
        self.assertEqual(target.wait(timeout=2), -signal.SIGTERM)
        self.assert_decoy_alive()

    def test_exit_between_verification_and_signal_is_harmless(self):
        target = self.child(target=True)
        send = signal.pidfd_send_signal
        def exit_before_signal(handle, sig):
            target.terminate()
            target.wait(timeout=2)
            self.pid_path.write_text(str(self.decoy.pid))
            return send(handle, sig)
        with mock.patch.object(signal, 'pidfd_send_signal', side_effect=exit_before_signal):
            self.player.stop_channel('main')
        self.assert_decoy_alive()

    def test_sigkill_uses_same_handle_after_pid_file_replacement(self):
        target = self.child(target=True, stubborn=True)
        send = signal.pidfd_send_signal
        calls = []
        def replace_after_term(handle, sig):
            calls.append((handle, sig))
            send(handle, sig)
            self.pid_path.write_text(str(self.decoy.pid))
        with mock.patch.object(signal, 'pidfd_send_signal', side_effect=replace_after_term):
            self.player.stop_channel('main')
        self.assertEqual(target.wait(timeout=2), -signal.SIGKILL)
        self.assertEqual([s for _, s in calls], [signal.SIGTERM, signal.SIGKILL])
        self.assertEqual(calls[0][0], calls[1][0])
        with self.assertRaises(OSError):
            os.fstat(calls[0][0])
        self.assert_decoy_alive()

    def test_reused_pid_already_belongs_to_unrelated_process(self):
        self.pid_path.write_text(str(self.decoy.pid))
        with mock.patch.object(signal, 'pidfd_send_signal') as send:
            self.player.stop_channel('main')
        send.assert_not_called()
        self.assert_decoy_alive()

    def test_process_exit_during_pidfd_open(self):
        target = self.child(target=True)
        pin = os.pidfd_open
        def gone(pid):
            target.terminate()
            target.wait(timeout=2)
            return pin(pid)
        with mock.patch.object(os, 'pidfd_open', side_effect=gone):
            self.player.stop_channel('main')
        self.assert_decoy_alive()

    def test_pidfd_failure_never_falls_back_to_numeric_signals(self):
        target = self.child(target=True)
        with mock.patch.object(os, 'pidfd_open', side_effect=OSError(errno.ENOSYS, 'unavailable')):
            with mock.patch.object(os, 'kill') as kill, mock.patch.object(os, 'killpg') as killpg:
                with self.assertRaises(OSError):
                    self.player.stop_channel('main')
                kill.assert_not_called()
                killpg.assert_not_called()
        self.assertIsNone(target.poll())
        self.assertTrue(self.pid_path.exists())
        self.assert_decoy_alive()


if __name__ == '__main__':
    unittest.main()
