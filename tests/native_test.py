"""Real Rust daemon stress, transport, MPRIS and asynchronous feed coverage.

Run with LOFI_TEST_BACKEND=rust and an explicit SKYLOFI_NATIVE executable on
tests/dbus-no-activation.conf. All audio is real mpv --ao=null on local WAVs.
Python reference imports do not validate the rewrite: these cases execute it.
"""
import json
import os
from pathlib import Path
import queue
import select
import shutil
import signal
import socket
import ssl
import subprocess
import sys
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import player_test
from mpris_test import CLIENT
import youtube_test
import recovery_test
import config_test


NATIVE = os.environ.get('LOFI_TEST_BACKEND') == 'rust'


class NativeFixture(unittest.TestCase):
    setUp = player_test.PlayerTest.setUp
    tearDown = player_test.PlayerTest.tearDown
    action = player_test.PlayerTest.action
    status = player_test.PlayerTest.status
    channel = player_test.PlayerTest.channel
    pid = player_test.PlayerTest.pid
    prop = player_test.PlayerTest.prop
    wait_for = player_test.PlayerTest.wait_for
    wait_prop = player_test.PlayerTest.wait_prop


@unittest.skipUnless(NATIVE, 'Rust executable integration; select LOFI_TEST_BACKEND=rust')
class NativeStressTest(NativeFixture):

    def controller(self):
        return int(self.pid('controller'))

    def start_all_channels(self):
        self.action('ui', 'fade', 'off')
        self.action('play')
        nature = next(category['stations'] for category in json.loads((self.plugin/'stations.json').read_text())['categories'] if category['id'] == 'ambience')
        for station in nature:
            self.action('nature', station['id'], 'on')
        return ['main', 'bg', *('nature-' + station['id'] for station in nature)]

    def pin(self, pid):
        handle = os.pidfd_open(pid)
        self.addCleanup(os.close, handle)
        return handle

    def test_parallel_first_commands_create_one_live_controller(self):
        clients = [subprocess.Popen([str(self.plugin/'lofi-player'), 'status'], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(8)]
        for client in clients:
            stdout, stderr = client.communicate(timeout=8)
            self.assertEqual(client.returncode, 0, stderr)
            self.assertTrue(json.loads(stdout)['native_backend'])
        controller = self.controller()
        self.assertGreater(controller, 0)
        self.assertTrue(Path(f'/proc/{controller}').exists())
        self.action('vol', 'master', '48')
        self.assertEqual(self.controller(), controller)

    def test_stopped_controller_with_voxtype_files_does_not_spin(self):
        vox = self.base/'runtime/voxtype'
        vox.mkdir()
        (vox/'pid').write_text(str(os.getpid()))
        (vox/'state').write_text('idle')
        config = self.base/'config/voxtype'
        config.mkdir(parents=True)
        (config/'config.toml').write_text('state_file = "auto"\n')
        self.assertFalse(self.status()['running'])
        pid = self.controller()
        def ticks():
            fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
            return int(fields[11]) + int(fields[12])
        time.sleep(.2)
        before = ticks()
        status_path = self.base/'runtime/sky.lofi/status.json'
        status_revision = status_path.stat().st_mtime_ns
        started = time.monotonic()
        time.sleep(2)
        cpu_fraction = (ticks() - before) / os.sysconf('SC_CLK_TCK') / (time.monotonic() - started)
        # Intentionally generous for CI: catches the observed118% self-induced
        # access-event loop, while not asserting benchmark-level precision.
        self.assertLess(cpu_fraction, .25, 'stopped controller spun instead of waiting for changed files')
        self.assertEqual(status_path.stat().st_mtime_ns, status_revision, 'idle controller kept rewriting unchanged status')


    def test_suspended_mpv_does_not_block_status_or_master_controls(self):
        self.action('bg', 'off')
        self.action('ui', 'fade', 'off')
        self.action('play')
        self.wait_prop('main', 'volume', 65)
        handle = self.pin(int(self.pid('main')))
        signal.pidfd_send_signal(handle, signal.SIGSTOP)
        def resume():
            try:
                signal.pidfd_send_signal(handle, signal.SIGCONT)
            except ProcessLookupError:
                pass
        self.addCleanup(resume)
        started = time.monotonic()
        self.assertTrue(self.status()['running'])
        self.assertLess(time.monotonic() - started, 1.0, 'status waited for unresponsive audio IPC')
        started = time.monotonic()
        self.action('vol', 'master', '40')
        self.assertLess(time.monotonic() - started, 1.0, 'master update waited for unresponsive audio IPC')
        resume()
        self.wait_prop('main', 'volume', 26)

    def test_eleven_channels_keep_independent_mix_under_concurrent_clients(self):
        channels = self.start_all_channels()
        self.assertEqual(len(channels), 11)
        updates = [('main', 43), ('bg', 17), *[(channel.removeprefix('nature-'), 20 + index * 5) for index, channel in enumerate(channels[2:])]]
        children = [subprocess.Popen([str(self.plugin/'lofi-player'), 'vol', channel, str(value)], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for channel, value in updates]
        for child in children:
            stdout, stderr = child.communicate(timeout=8)
            self.assertEqual(child.returncode, 0, stderr)
            self.assertIsInstance(json.loads(stdout), dict)
        state = self.status()
        self.assertEqual(state['main_volume'], 43)
        self.assertEqual(state['bg_volume'], 17)
        layers = {layer['id']: layer for layer in state['nature_layers']}
        for identity, value in updates[2:]:
            self.assertEqual(layers[identity]['volume'], value)
            self.wait_prop('nature-' + identity, 'volume', value)
        self.action('vol', 'master', '0')
        for channel in channels:
            self.wait_prop(channel, 'volume', 0)
        self.action('pause')
        for channel in channels:
            self.wait_for(lambda channel=channel: self.prop(channel, 'pause'))
        self.action('resume')
        self.action('vol', 'master', '100')
        for channel, (_, value) in zip(channels, updates):
            self.wait_prop(channel, 'volume', value)

    def test_crashed_controller_reconnects_and_stop_reaps_all_previous_audio(self):
        channels = self.start_all_channels()
        audio = [self.pin(int(self.pid(channel))) for channel in channels]
        controller = self.pin(self.controller())
        signal.pidfd_send_signal(controller, signal.SIGKILL)
        self.assertTrue(select.select([controller], [], [], 3)[0])
        self.status()
        self.assertNotEqual(self.controller(), 0)
        self.action('ui', 'fade', 'off')
        self.action('stop')
        for handle in audio:
            self.assertTrue(select.select([handle], [], [], 3)[0], 'old audio survived controller recovery and Stop')
        runtime = self.base/'runtime/sky.lofi'
        self.assertFalse(any(path.stem in channels for path in runtime.glob('*.pid')))

    def test_stop_ignores_replaced_pid_file_and_foreign_runtime_process(self):
        self.action('ui', 'fade', 'off')
        self.action('play')
        audio = self.pin(int(self.pid('main')))
        foreign = str(self.base/'foreign/runtime/sky.lofi/sockets/main.sock')
        decoy = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)', '--input-ipc-server=' + foreign])
        def cleanup():
            if decoy.poll() is None:
                decoy.terminate()
            decoy.wait(timeout=3)
        self.addCleanup(cleanup)
        (self.base/'runtime/sky.lofi/main.pid').write_text(str(decoy.pid))
        self.action('stop')
        self.assertIsNone(decoy.poll(), 'Stop signalled a foreign process from a stale PID file')
        self.assertTrue(select.select([audio], [], [], 3)[0], 'actual audio was leaked after a replaced PID file')

    def test_partial_or_oversized_control_client_does_not_block_other_clients(self):
        self.status()
        endpoint = self.base/'runtime/sky.lofi/controller.sock'
        for payload in (b'{"args":[', b'x' * 65537):
            with self.subTest(size=len(payload)), socket.socket(socket.AF_UNIX) as stalled:
                stalled.settimeout(1)
                stalled.connect(str(endpoint))
                try:
                    stalled.sendall(payload)
                except BrokenPipeError:
                    pass
                started = time.monotonic()
                self.action('vol', 'master', '47')
                self.assertEqual(self.status()['master_volume'], 47)
                self.assertLess(time.monotonic() - started, 1.0)

    def test_stdio_matches_reply_ids_amid_unsolicited_status_events(self):
        process = subprocess.Popen([str(self.plugin/'lofi-player'), '--stdio'], env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        frames = queue.Queue()
        def read():
            for line in process.stdout:
                frames.put(line)
            frames.put('')
        reader = threading.Thread(target=read, daemon=True)
        reader.start()
        try:
            first = json.loads(frames.get(timeout=3))
            self.assertEqual(first['event'], 'status')
            for identity in range(1, 31):
                process.stdin.write(json.dumps({'id': identity, 'args': ['vol', 'master', str(identity)]}) + '\n')
            process.stdin.flush()
            replies = {}
            deadline = time.monotonic() + 5
            while len(replies) < 30:
                frame = json.loads(frames.get(timeout=max(.001, deadline - time.monotonic())))
                if 'id' in frame:
                    self.assertNotIn(frame['id'], replies)
                    replies[frame['id']] = frame
            for identity, frame in replies.items():
                self.assertTrue(frame['ok'], frame)
                self.assertEqual(frame['status']['master_volume'], identity)
            self.assertEqual(self.status()['master_volume'], 30)
        finally:
            process.stdin.close()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=3)
            reader.join(timeout=1)
            process.stdout.close()
            process.stderr.close()

    def test_settings_save_failure_is_reported_to_control_client(self):
        self.status()
        path = self.base/'state/sky.lofi/settings.json'
        original = path.read_bytes()
        path.unlink()
        path.mkdir()
        try:
            result = self.action('vol', 'main', '23', check=False)
            self.assertNotEqual(result.returncode, 0, 'volume reported success despite failed persistence')
            self.assertTrue(result.stderr.strip(), 'persistence failure has no actionable diagnostic')
        finally:
            path.rmdir()
            path.write_bytes(original)

    def test_python_to_rust_transition_retires_legacy_services_at_same_root(self):
        entry = self.plugin/'lofi-player'
        native_entry = entry.read_bytes()
        entry.write_text('#!/usr/bin/env python3\nimport sys\nsys.dont_write_bytecode=True\nfrom lofi_backend import main\nmain()\n')
        try:
            self.action('ui', 'fade', 'off')
            self.action('play')
            self.action('noise', 'noise-rain')
            old_services = [self.pin(int(self.pid(channel))) for channel in ('volume', 'mpris')]
            old_audio = [self.pin(int(self.pid(channel))) for channel in ('main', 'bg', 'nature-noise-rain')]
        finally:
            entry.write_bytes(native_entry)
        decoy = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)', str(self.plugin/'foreign/lofi-player'), '--watch'])
        self.addCleanup(lambda: (decoy.kill() if decoy.poll() is None else None, decoy.wait()))
        self.assertTrue(self.status()['native_backend'])
        for handle in old_services:
            self.assertTrue(select.select([handle], [], [], 3)[0], 'legacy service still races native state/volume/MPRIS')
        self.action('play')
        self.action('vol', 'main', '27')
        self.wait_prop('main', 'volume', 27)
        time.sleep(.3)
        self.assertAlmostEqual(self.prop('main', 'volume'), 27, places=1)
        self.assertIsNone(decoy.poll(), 'migration signalled a foreign plugin worker')
        self.action('stop')
        for handle in old_audio:
            self.assertTrue(select.select([handle], [], [], 3)[0], 'legacy audio leaked after native Stop')

    def test_changed_native_executable_replaces_old_daemon(self):
        self.action('ui', 'fade', 'off')
        self.action('play')
        original = self.controller()
        handle = self.pin(original)
        upgraded = self.base/'skylofi-upgrade-fixture'
        shutil.copyfile(self.env['SKYLOFI_NATIVE'], upgraded)
        # Linux permits trailing non-loadable ELF data. Distinct bytes/inode
        # simulate an installed binary replacement without building in a test.
        with upgraded.open('ab') as output:
            output.write(b'\nSkylofi isolated binary replacement fixture\n')
        upgraded.chmod(0o755)
        self.env['SKYLOFI_NATIVE'] = str(upgraded)
        self.assertTrue(self.status()['native_backend'])
        self.assertNotEqual(self.controller(), original, 'new executable silently kept the previous daemon')
        self.assertTrue(select.select([handle], [], [], 3)[0], 'old native daemon survived executable replacement')


@unittest.skipUnless(NATIVE, 'Rust MPRIS daemon integration')
class NativeMprisTest(NativeFixture):
    def wait_mpris(self):
        def has_owner():
            result = subprocess.run(['gdbus', 'call', '--session', '--dest', 'org.freedesktop.DBus', '--object-path', '/org/freedesktop/DBus', '--method', 'org.freedesktop.DBus.NameHasOwner', 'org.mpris.MediaPlayer2.sky.lofi'], env=self.env, capture_output=True, text=True, timeout=3)
            return 'true' in result.stdout
        self.wait_for(has_owner)

    def mpris(self, method, *args):
        return subprocess.run(['gdbus', 'call', '--session', '--dest', 'org.mpris.MediaPlayer2.sky.lofi', '--object-path', '/org/mpris/MediaPlayer2', '--method', method, *args], env=self.env, capture_output=True, text=True, check=True, timeout=3).stdout

    def test_transport_properties_and_master_volume(self):
        self.action('ui', 'fade', 'off')
        self.action('play')
        self.wait_mpris()
        self.wait_for(lambda: 'Playing' in self.mpris('org.freedesktop.DBus.Properties.Get', 'org.mpris.MediaPlayer2.Player', 'PlaybackStatus'))
        self.mpris('org.mpris.MediaPlayer2.Player.Pause')
        self.wait_for(lambda: self.status()['paused'])
        self.mpris('org.mpris.MediaPlayer2.Player.Play')
        self.wait_for(lambda: not self.status()['paused'])
        self.mpris('org.freedesktop.DBus.Properties.Set', 'org.mpris.MediaPlayer2.Player', 'Volume', '<0.25>')
        self.wait_for(lambda: self.status()['master_volume'] == 25)
        self.wait_prop('main', 'volume', 16.25)
        self.mpris('org.mpris.MediaPlayer2.Player.Stop')
        self.wait_for(lambda: not self.status()['running'])

    def test_voxtype_pair_preserves_manual_stop_and_respects_disabled_ducking(self):
        self.action('ui', 'fade', 'off')
        self.action('play')
        self.wait_mpris()
        shutil.copy2(Path(sys.executable).resolve(), self.bin/'voxtype')
        env = dict(self.env, PYTHONHOME=sys.base_prefix)
        client = subprocess.Popen([str(self.bin/'voxtype'), '-u', '-c', CLIENT], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        def invoke(method):
            client.stdin.write(method + '\n')
            client.stdin.flush()
            self.assertTrue(select.select([client.stdout], [], [], 3)[0], 'native MPRIS source detection deadlocked')
            raw = client.stdout.readline()
            self.assertTrue(raw, client.stderr.read() if client.poll() is not None else 'client closed')
            return json.loads(raw)
        try:
            # Real VoxType issues Pause before writing recording state.
            pause = invoke('Pause')
            self.assertFalse(self.status()['paused'])
            self.action('stop')
            resume = invoke('Play')
            self.assertEqual(pause['pid'], resume['pid'])
            self.assertNotEqual(pause['sender'], resume['sender'])
            self.assertFalse(self.status()['running'], 'paired dictation resume undid manual Stop')
            self.action('play')
            self.action('ducking', 'off')
            invoke('Pause')
            self.wait_for(lambda: self.status()['paused'])
            invoke('Play')
            self.wait_for(lambda: not self.status()['paused'])
        finally:
            client.terminate()
            client.wait(timeout=3)
            client.stdin.close()
            client.stdout.close()
            client.stderr.close()


@unittest.skipUnless(NATIVE, 'Rust native extractor tree cancellation')
class NativeCancellationTest(NativeFixture):
    setUp = youtube_test.YoutubeIntegrationTest.setUp

    def test_deep_extractor_cancellation_does_not_leave_frozen_or_orphaned_helpers(self):
        # Exceeds the initial implementation's recursion budget; exercises the
        # cancellation error path on genuine Linux children, not mocked PIDs.
        self.env['LOFI_TEST_EXTRACTOR_DELAY'] = '30'
        self.env['LOFI_TEST_EXTRACTOR_TREE'] = '20'
        self.action('shutdown')
        self.action('youtube-add', youtube_test.URL)
        self.action('start', youtube_test.ID)
        self.wait_for(lambda: (self.tree_pids/'0').exists())
        descendants = {}
        for path in [self.extractor_pid, *self.tree_pids.iterdir()]:
            pid = int(path.read_text())
            descriptor = os.pidfd_open(pid)
            descendants[pid] = descriptor
            def cleanup(handle=descriptor):
                if not select.select([handle], [], [], 0)[0]:
                    signal.pidfd_send_signal(handle, signal.SIGKILL)
                os.close(handle)
            self.addCleanup(cleanup)
        started = time.monotonic()
        self.action('stop')
        self.assertLess(time.monotonic() - started, 3, 'bounded extractor cancellation blocked transport')
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            remaining = [pid for pid, descriptor in descendants.items() if not select.select([descriptor], [], [], 0)[0]]
            if not remaining:
                break
            time.sleep(.02)
        frozen = []
        for pid in remaining:
            try:
                state = next(line.split()[1] for line in Path(f'/proc/{pid}/status').read_text().splitlines() if line.startswith('State:'))
                if state in ('T', 't'):
                    frozen.append(pid)
            except (OSError, StopIteration):
                pass
        self.assertFalse(frozen, 'cancellation failure left helpers SIGSTOP suspended: ' + str(frozen))
        self.assertFalse(remaining, 'cancellation leaked extractor descendants: ' + str(remaining))


@unittest.skipUnless(NATIVE, 'Rust asynchronous HTTPS feed integration')
class NativeFeedTest(NativeFixture):
    def setUp(self):
        super().setUp()
        self.entered = threading.Event()
        self.release = threading.Event()
        self.delayed = False
        fixture = self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_GET(self):
                if self.path == '/feed.xml':
                    fixture.entered.set()
                    if fixture.delayed:
                        fixture.release.wait(timeout=15)
                    data = fixture.feed
                    mime = 'application/rss+xml'
                elif self.path == '/tone.wav':
                    data = (fixture.base/'tone.wav').read_bytes()
                    mime = 'audio/wav'
                elif self.path == '/redirect':
                    self.send_response(302)
                    self.send_header('Location', f'http://localhost:{fixture.server.server_port}/feed.xml')
                    self.end_headers()
                    return
                else:
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header('Content-Type', mime)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                    pass
        ca = self.base/'fixture-ca.crt'
        ca_key = self.base/'fixture-ca.key'
        certificate = self.base/'server.crt'
        key = self.base/'server.key'
        csr = self.base/'server.csr'
        extensions = self.base/'certificate.ext'
        extensions.write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n')
        commands = [
            ['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj', '/CN=Skylofi isolated test CA', '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign', '-keyout', str(ca_key), '-out', str(ca)],
            ['openssl', 'req', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost', '-keyout', str(key), '-out', str(csr)],
            ['openssl', 'x509', '-req', '-in', str(csr), '-CA', str(ca), '-CAkey', str(ca_key), '-set_serial', '1', '-days', '2', '-extfile', str(extensions), '-out', str(certificate)],
        ]
        for command in commands:
            subprocess.run(command, capture_output=True, check=True, timeout=10)
        self.env['SSL_CERT_FILE'] = str(ca)
        self.env['LOFI_TEST_CA'] = str(ca)
        (self.bin/'mpv').write_text('#!/bin/sh\nexec /usr/bin/mpv --ao=null --tls-ca-file="$LOFI_TEST_CA" --loop-file=inf "$@"\n')
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certificate, key)
        self.server.socket = context.wrap_socket(self.server.socket, server_side=True)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.addCleanup(self.release.set)
        self.feed = f'<rss><channel><item><enclosure url="https://localhost:{self.server.server_port}/tone.wav" type="audio/wav"/></item></channel></rss>'.encode()
        self.update_feed_url('/feed.xml')
        self.action('ui', 'fade', 'off')

    def update_feed_url(self, path):
        catalog_path = self.plugin/'stations.json'
        catalog = json.loads(catalog_path.read_text())
        for category in catalog['categories']:
            for station in category['stations']:
                if station['id'] == 'voice-changelog':
                    station.update(kind='podcast', url=f'https://localhost:{self.server.server_port}{path}')
        catalog_path.write_text(json.dumps(catalog))

    def test_https_feed_uses_os_trust_and_starts_real_background_audio(self):
        self.action('play')
        self.action('bg', 'voice-changelog')
        self.wait_for(lambda: self.status()['bg_running'])
        self.wait_for(lambda: self.prop('bg', 'time-pos') is not None)
        self.assertTrue(self.entered.is_set())
        playlist = list((self.base/'runtime/sky.lofi').glob('*.m3u'))
        self.assertTrue(playlist, 'native feed did not publish its resolved playlist')
        self.assertIn(f'https://localhost:{self.server.server_port}/tone.wav', playlist[0].read_text())

    def test_delayed_feed_cannot_block_transport_or_restart_after_stop(self):
        self.delayed = True
        self.action('play')
        started = time.monotonic()
        self.action('bg', 'voice-changelog')
        self.assertLess(time.monotonic() - started, 1.0)
        self.assertTrue(self.entered.wait(timeout=3), 'native HTTPS worker never reached fixture')
        for command in ('pause', 'stop'):
            started = time.monotonic()
            self.action(command)
            self.assertLess(time.monotonic() - started, 1.0, 'slow feed blocked ' + command)
        self.release.set()
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            state = self.status()
            self.assertFalse(state['running'])
            self.assertFalse(state['bg_running'], 'late feed result restarted stopped audio')
            time.sleep(.05)

    def test_late_feed_does_not_replace_new_background_selection(self):
        self.delayed = True
        self.action('play')
        self.action('bg', 'voice-changelog')
        self.assertTrue(self.entered.wait(timeout=3))
        self.action('bg', 'talk-bbc-world')
        self.wait_for(lambda: self.status()['bg_running'])
        original = self.pid('bg')
        self.release.set()
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            self.assertEqual(self.status()['bg_station'], 'talk-bbc-world')
            self.assertEqual(self.pid('bg'), original, 'late feed result replaced newer audio')
            time.sleep(.05)

    def test_dtd_and_https_downgrade_redirect_do_not_start_audio(self):
        self.feed = b'<!DOCTYPE rss [<!ENTITY secret SYSTEM "file:///etc/passwd">]><rss><enclosure url="&secret;"/></rss>'
        self.action('play')
        self.action('bg', 'voice-changelog')
        self.assertTrue(self.entered.wait(timeout=3))
        time.sleep(.3)
        self.assertFalse(self.status()['bg_running'], 'DTD feed was accepted')
        self.action('bg', 'off')
        self.update_feed_url('/redirect')
        self.action('bg', 'voice-changelog')
        time.sleep(.3)
        self.assertFalse(self.status()['bg_running'], 'HTTPS feed downgraded to insecure HTTP')


@unittest.skipUnless(NATIVE, 'Rust recovery, settings migration and catalog updates')
class NativeRecoveryTest(NativeFixture):
    # Reuse behavior assertions through the actual selected Rust CLI. The two
    # Python-specific code-injection/worker-hash tests are separately replaced
    # by native HTTPS cancellation and executable migration tests above.
    wait_volume = recovery_test.RecoveryIntegrationTest.wait_volume
    wait_retry = recovery_test.RecoveryIntegrationTest.wait_retry
    assert_no_music_for = recovery_test.RecoveryIntegrationTest.assert_no_music_for
    remove_music_station = recovery_test.RecoveryIntegrationTest.remove_music_station
    test_reconnect_preserves_voice_and_each_nature_process = recovery_test.RecoveryIntegrationTest.test_reconnect_preserves_voice_and_each_nature_process
    test_pause_cancels_retry_even_without_other_channels = recovery_test.RecoveryIntegrationTest.test_pause_cancels_retry_even_without_other_channels
    test_stop_cancels_retry_and_does_not_restart_from_status = recovery_test.RecoveryIntegrationTest.test_stop_cancels_retry_and_does_not_restart_from_status
    test_new_station_replaces_pending_retry = recovery_test.RecoveryIntegrationTest.test_new_station_replaces_pending_retry
    test_removed_playing_station_replaces_audio_without_restarting_other_layers = recovery_test.RecoveryIntegrationTest.test_removed_playing_station_replaces_audio_without_restarting_other_layers
    test_removed_paused_station_waits_for_resume_and_keeps_valid_default = recovery_test.RecoveryIntegrationTest.test_removed_paused_station_waits_for_resume_and_keeps_valid_default
    test_removed_stopped_station_does_not_start_audio = recovery_test.RecoveryIntegrationTest.test_removed_stopped_station_does_not_start_audio
    test_layers_keep_individual_balance_under_master_and_voxtype = recovery_test.RecoveryIntegrationTest.test_layers_keep_individual_balance_under_master_and_voxtype
    test_legacy_nature_selection_migrates_once_with_same_volume = recovery_test.RecoveryIntegrationTest.test_legacy_nature_selection_migrates_once_with_same_volume
    test_layered_settings_migrate_without_changing_active_or_saved_loudness = recovery_test.RecoveryIntegrationTest.test_layered_settings_migrate_without_changing_active_or_saved_loudness
    test_legacy_nature_volume_command_sets_only_enabled_layers_directly = recovery_test.RecoveryIntegrationTest.test_legacy_nature_volume_command_sets_only_enabled_layers_directly
    test_corrupt_preferences_and_empty_catalog_leave_stop_usable = config_test.ConfigRecoveryTest.test_corrupt_preferences_and_empty_catalog_leave_stop_usable


if __name__ == '__main__':
    unittest.main()
