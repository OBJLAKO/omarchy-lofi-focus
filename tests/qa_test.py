"""Independent native MPRIS lifecycle regressions on silent private buses.

These cases never play audio. Run with LOFI_TEST_BACKEND=rust and an explicit
SKYLOFI_NATIVE, inside tests/dbus-no-activation.conf.
"""
import os
from pathlib import Path
import select
import subprocess
import sys
import unittest

from native_test import NativeFixture


NAME = 'org.mpris.MediaPlayer2.sky.lofi'
OWNER = r'''
import sys
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
reply = bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
                     'org.freedesktop.DBus', 'RequestName',
                     GLib.Variant('(su)', ('org.mpris.MediaPlayer2.sky.lofi', 0)),
                     GLib.VariantType.new('(u)'), Gio.DBusCallFlags.NONE,
                     3000, None)
assert reply.unpack() == (1,), reply
print(bus.get_unique_name(), flush=True)
sys.stdin.readline()
bus.close_sync(None)
'''


@unittest.skipUnless(os.environ.get('LOFI_TEST_BACKEND') == 'rust',
                     'Native executable lifecycle integration')
class NativeMprisLifecycleTest(NativeFixture):
    def owner(self, env=None):
        result = subprocess.run([
            'gdbus', 'call', '--session', '--dest', 'org.freedesktop.DBus',
            '--object-path', '/org/freedesktop/DBus', '--method',
            'org.freedesktop.DBus.GetNameOwner', NAME,
        ], env=env or self.env, capture_output=True, text=True, timeout=3)
        return result.stdout.strip() if result.returncode == 0 else ''

    def mpris_volume(self, value, env=None):
        return subprocess.run([
            'gdbus', 'call', '--session', '--dest', NAME,
            '--object-path', '/org/mpris/MediaPlayer2', '--method',
            'org.freedesktop.DBus.Properties.Set',
            'org.mpris.MediaPlayer2.Player', 'Volume', f'<{value}>',
        ], env=env or self.env, capture_output=True, text=True,
            check=True, timeout=3)

    def cleanup_process(self, process):
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=3)
        for stream in (process.stdin, process.stdout, process.stderr):
            if stream:
                stream.close()

    def wait_line(self, process):
        self.assertTrue(select.select([process.stdout], [], [], 3)[0],
                        'private service did not become ready')
        line = process.stdout.readline().strip()
        self.assertTrue(line, 'private service exited before becoming ready')
        return line

    def start_bus(self):
        config = Path(__file__).with_name('dbus-no-activation.conf')
        bus = subprocess.Popen([
            'dbus-daemon', '--nofork', '--config-file=' + str(config),
            '--address=' + self.env['DBUS_SESSION_BUS_ADDRESS'], '--print-address',
        ], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True)
        self.addCleanup(self.cleanup_process, bus)
        self.wait_line(bus)
        return bus

    def test_temporary_name_owner_releases_to_native_without_controller_restart(self):
        holder = subprocess.Popen([sys.executable, '-u', '-c', OWNER],
                                  env=self.env, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True)
        self.addCleanup(self.cleanup_process, holder)
        previous = self.wait_line(holder)
        self.assertIn(previous, self.owner())
        self.assertTrue(self.status()['native_backend'])
        controller = self.pid('controller')
        # A CLI command works while another player holds the public identity.
        self.action('vol', 'master', '47')
        holder.stdin.write('\n')
        holder.stdin.flush()
        holder.wait(timeout=3)
        self.wait_for(lambda: bool(self.owner()) and previous not in self.owner())
        self.assertEqual(self.pid('controller'), controller)
        self.mpris_volume(.31)
        self.wait_for(lambda: self.status()['master_volume'] == 31)

    def test_session_bus_appearing_after_controller_start_restores_mpris(self):
        endpoint = self.base / 'late-session-bus.sock'
        self.env['DBUS_SESSION_BUS_ADDRESS'] = 'unix:path=' + str(endpoint)
        self.assertTrue(self.status()['native_backend'])
        controller = self.pid('controller')
        self.assertFalse(self.owner())
        self.start_bus()
        self.wait_for(lambda: bool(self.owner()))
        self.assertEqual(self.pid('controller'), controller)
        self.mpris_volume(.29)
        self.wait_for(lambda: self.status()['master_volume'] == 29)

    def test_session_bus_restart_restores_mpris_without_controller_restart(self):
        endpoint = self.base / 'restart-session-bus.sock'
        self.env['DBUS_SESSION_BUS_ADDRESS'] = 'unix:path=' + str(endpoint)
        bus = self.start_bus()
        self.assertTrue(self.status()['native_backend'])
        self.wait_for(lambda: bool(self.owner()))
        controller = self.pid('controller')
        bus.terminate()
        bus.wait(timeout=3)
        self.assertFalse(self.owner())
        self.start_bus()
        self.wait_for(lambda: bool(self.owner()))
        self.assertEqual(self.pid('controller'), controller)
        self.mpris_volume(.27)
        self.wait_for(lambda: self.status()['master_volume'] == 27)


if __name__ == '__main__':
    unittest.main()
