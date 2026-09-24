"""Exercise source-aware transport against the real bridge on a private D-Bus.

No desktop players or settings are used. The VoxType stand-in is a copied
Python executable so /proc/<pid>/exe, rather than argv[0], identifies it.
"""
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


SOURCE = Path(__file__).resolve().parents[1]
CLIENT = r'''
import json, os, sys
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib
for line in sys.stdin:
    # VoxType opens a fresh connection for resume, but keeps the same daemon PID.
    bus = Gio.DBusConnection.new_for_address_sync(
        os.environ['DBUS_SESSION_BUS_ADDRESS'],
        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT |
        Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
    sender = bus.get_unique_name()
    bus.call_sync('org.mpris.MediaPlayer2.sky.lofi', '/org/mpris/MediaPlayer2',
                  'org.mpris.MediaPlayer2.Player', line.strip(), None, None,
                  Gio.DBusCallFlags.NONE, 2000, None)
    print(json.dumps({'pid': os.getpid(), 'sender': sender}), flush=True)
    bus.close_sync(None)
'''


class MprisIntegrationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.processes = []
        self.files = []
        self.addCleanup(self.cleanup_processes)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        shutil.copy2(Path(sys.executable).resolve(), self.bin / 'voxtype')
        self.runtime = self.base / 'runtime'
        self.runtime.mkdir(mode=0o700)
        self.settings = self.base / 'state/sky.lofi/settings.json'
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text(json.dumps({'ducking': True}))
        self.actions = self.base / 'actions.jsonl'
        player = self.base / 'player'
        player.write_text(
            '#!/usr/bin/env python3\nimport json, os, sys\n'
            'with open(os.environ["TEST_ACTION_LOG"], "a") as f:\n'
            '    f.write(json.dumps({"args": sys.argv[1:], '
            '"source": os.environ.get("LOFI_CONTROL_SOURCE")}) + "\\n")\n')
        player.chmod(0o755)
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.runtime),
                        XDG_STATE_HOME=str(self.base / 'state'),
                        XDG_CONFIG_HOME=str(self.base / 'config'),
                        PATH=str(self.bin) + ':' + os.environ['PATH'],
                        PYTHONHOME=sys.base_prefix,
                        TEST_ACTION_LOG=str(self.actions))
        self.bus = self.start(['dbus-daemon', '--session', '--nofork', '--print-address=1'])
        self.env['DBUS_SESSION_BUS_ADDRESS'] = self.read_line(self.bus).strip()
        self.bridge = self.start([sys.executable, str(SOURCE / 'lofi-mpris'), str(player)])
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            result = subprocess.run([
                'gdbus', 'call', '--session', '--dest', 'org.freedesktop.DBus',
                '--object-path', '/org/freedesktop/DBus', '--method',
                'org.freedesktop.DBus.NameHasOwner', 'org.mpris.MediaPlayer2.sky.lofi'],
                env=self.env, capture_output=True, text=True, timeout=2)
            if 'true' in result.stdout:
                break
            time.sleep(.02)
        else:
            self.fail('Bridge did not acquire its private bus name')
        self.regular = self.start([sys.executable, '-u', '-c', CLIENT])
        self.voxtype = self.start([str(self.bin / 'voxtype'), '-u', '-c', CLIENT])

    def start(self, command):
        stderr = (self.base / ('process-%d.log' % len(self.processes))).open('w+')
        self.files.append(stderr)
        process = subprocess.Popen(command, env=self.env, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=stderr, text=True)
        self.processes.append(process)
        return process

    def read_line(self, process):
        ready, _, _ = select.select([process.stdout], [], [], 3)
        self.assertTrue(ready, 'D-Bus request timed out (possible bridge deadlock)')
        line = process.stdout.readline()
        if not line:
            logs = []
            for file in self.files:
                file.flush()
                file.seek(0)
                logs.append(file.read())
            self.fail('Child exited before replying: ' + '\n'.join(logs))
        return line

    def call(self, client, method):
        client.stdin.write(method + '\n')
        client.stdin.flush()
        return json.loads(self.read_line(client))

    def logged(self):
        return [json.loads(line) for line in self.actions.read_text().splitlines()] if self.actions.exists() else []

    def wait_actions(self, expected):
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if [x['args'] for x in self.logged()] == expected:
                return
            time.sleep(.01)
        self.assertEqual([x['args'] for x in self.logged()], expected)

    def assert_actions_stay(self, expected):
        deadline = time.monotonic() + .2
        while time.monotonic() < deadline:
            self.assertEqual([x['args'] for x in self.logged()], expected)
            time.sleep(.02)

    def cleanup_processes(self):
        for process in reversed(self.processes):
            if process.poll() is None:
                process.terminate()
        for process in reversed(self.processes):
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
            process.stdin.close()
            process.stdout.close()
        for file in self.files:
            file.close()

    def test_regular_transport_works_during_dictation(self):
        state = self.runtime / 'voxtype/state'
        state.parent.mkdir()
        state.write_text('recording')
        self.call(self.regular, 'Pause')
        self.wait_actions([['pause']])
        self.call(self.regular, 'Play')
        self.wait_actions([['pause'], ['play']])
        self.assertTrue(self.logged()[0]['source'].endswith(':Pause'))

    def test_voxtype_pause_before_state_write_and_resume_on_new_connection(self):
        self.assertFalse((self.runtime / 'voxtype/state').exists())
        pause = self.call(self.voxtype, 'Pause')
        play = self.call(self.voxtype, 'Play')
        self.assertEqual(pause['pid'], play['pid'])
        self.assertNotEqual(pause['sender'], play['sender'])
        self.assert_actions_stay([])

    def test_paired_resume_keeps_manual_stop_after_ducking_disabled(self):
        self.call(self.voxtype, 'Pause')
        self.call(self.regular, 'Stop')
        self.wait_actions([['stop']])
        self.settings.write_text(json.dumps({'ducking': False}))
        self.call(self.voxtype, 'Play')
        self.assert_actions_stay([['stop']])
        # The suppression token is consumed; a new dictation uses normal pause.
        self.call(self.voxtype, 'Pause')
        self.wait_actions([['stop'], ['pause']])
        self.call(self.voxtype, 'Play')
        self.wait_actions([['stop'], ['pause'], ['play']])

    def test_voxtype_transport_works_with_ducking_disabled(self):
        self.settings.write_text(json.dumps({'ducking': False}))
        self.call(self.voxtype, 'Pause')
        self.wait_actions([['pause']])
        self.call(self.voxtype, 'Play')
        self.wait_actions([['pause'], ['play']])


if __name__ == '__main__':
    unittest.main()
