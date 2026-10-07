"""YouTube validation and playback through real mpv with an offline extractor."""
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import sys
import threading
import subprocess
import time
import unittest
import wave
import signal
import socket

import player_test
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lofi_youtube import canonical_url, saved_entries

URL = 'https://www.youtube.com/watch?v=BaW_jenozKc'
ID = 'youtube-BaW_jenozKc'


class YoutubeURLTest(unittest.TestCase):
    def test_supported_links_are_canonical_and_tracking_is_removed(self):
        for url in (URL + '&list=ignored&index=2', 'https://youtu.be/BaW_jenozKc?si=tracking',
                    'https://m.youtube.com/watch?v=BaW_jenozKc',
                    'https://www.youtube.com/shorts/BaW_jenozKc',
                    'https://www.youtube.com/live/BaW_jenozKc', 'youtu.be/BaW_jenozKc'):
            self.assertEqual(canonical_url(url), URL)

    def test_rejects_other_hosts_schemes_playlist_and_option_injection(self):
        for url in ('file:///etc/passwd', '--script=evil', 'https://youtube.com.evil.test/watch?v=BaW_jenozKc',
                    'https://youtube.com@evil.test/watch?v=BaW_jenozKc',
                    'https://www.youtube.com:8443/watch?v=BaW_jenozKc',
                    'http://youtube.com/watch?v=BaW_jenozKc',
                    'https://youtube.com/playlist?list=abc', URL + '\n--exec=evil',
                    URL + '&v=another', 'https://youtube.com/watch?v=../../other'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                canonical_url(url)

    def test_saved_data_is_revalidated_deduplicated_and_bounded(self):
        entries = saved_entries([None, {'url': 'file:///etc/passwd'}, {'url': URL, 'position': float('nan')}, {'url': URL}])
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]['id'], ID)
        self.assertEqual(entries[0]['position'], 0)


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        # mpv needs HTTP Range support for accurate resume/seek tests.
        data = Path(self.directory, 'tone.wav').read_bytes()
        start = 0
        if self.headers.get('Range', '').startswith('bytes='):
            start = int(self.headers['Range'].split('=')[1].split('-')[0])
            self.send_response(206)
            self.send_header('Content-Range', f'bytes {start}-{len(data)-1}/{len(data)}')
        else:
            self.send_response(200)
        self.send_header('Content-Type', 'audio/wav')
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(len(data) - start))
        self.end_headers()
        try:
            self.wfile.write(data[start:])
        except (BrokenPipeError, ConnectionResetError):
            pass


class YoutubeIntegrationTest(unittest.TestCase):
    tearDown = player_test.PlayerTest.tearDown
    action = player_test.PlayerTest.action
    status = player_test.PlayerTest.status
    channel = player_test.PlayerTest.channel
    pid = player_test.PlayerTest.pid
    prop = player_test.PlayerTest.prop
    wait_for = player_test.PlayerTest.wait_for
    wait_prop = player_test.PlayerTest.wait_prop

    def setUp(self):
        player_test.PlayerTest.setUp(self)
        self.env['XDG_CONFIG_HOME'] = str(self.base/'config')
        with wave.open(str(self.base/'tone.wav'), 'wb') as audio:
            audio.setparams((1, 2, 8000, 0, 'NONE', 'not compressed'))
            audio.writeframes(b'\x00\x00' * 8000 * 90)
        (self.bin/'mpv').write_text('#!/bin/sh\nexec /usr/bin/mpv --ao=null "$@"\n')
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(self.base)))
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        payload = dict(id='BaW_jenozKc', title='Offline test conversation',
                       url=f'http://127.0.0.1:{self.server.server_port}/tone.wav',
                       ext='wav', protocol='http', duration=90, is_live=False)
        self.extractor_log = self.base/'extractor-args.json'
        self.extractor_pid = self.base/'extractor.pid'
        self.helper_pid = self.base/'helper.pid'
        self.tree_pids = self.base/'extractor-tree'
        helper_code = (
            'import os,sys,time,subprocess\nfrom pathlib import Path\n'
            'depth=int(sys.argv[1]); directory=Path(sys.argv[2]); directory.mkdir(exist_ok=True)\n'
            '(directory/str(depth)).write_text(str(os.getpid()))\n'
            'if depth>0: subprocess.Popen([sys.executable,"-c",sys.argv[3],str(depth-1),str(directory),sys.argv[3]])\n'
            'time.sleep(30)\n')
        script = ('#!/usr/bin/env python3\nimport json,os,sys,time,subprocess\nfrom pathlib import Path\n'
                  f'Path({str(self.extractor_log)!r}).write_text(json.dumps(sys.argv[1:]))\n'
                  f'Path({str(self.extractor_pid)!r}).write_text(str(os.getpid()))\n'
                  'if os.environ.get("LOFI_TEST_EXTRACTOR_DELAY"):\n'
                  f'    code = {helper_code!r}\n'
                  f'    helper = subprocess.Popen([sys.executable, "-c", code, os.environ.get("LOFI_TEST_EXTRACTOR_TREE", "0"), {str(self.tree_pids)!r}, code])\n'
                  f'    Path({str(self.helper_pid)!r}).write_text(str(helper.pid))\n'
                  'time.sleep(float(os.environ.get("LOFI_TEST_EXTRACTOR_DELAY", "0")))\n'
                  f'payload = json.loads({json.dumps(payload)!r})\n'
                  'if os.environ.get("LOFI_TEST_EXTRACTOR_LIVE"): payload["is_live"] = True\n'
                  'if os.environ.get("LOFI_TEST_EXTRACTOR_UNKNOWN"): payload.pop("is_live", None)\n'
                  'print(json.dumps(payload))\n')
        (self.bin/'yt-dlp').write_text(script)
        (self.bin/'yt-dlp').chmod(0o755)
        self.action('ui', 'fade', 'off')

    def start_video(self):
        self.action('youtube-add', URL)
        self.action('start', ID)
        self.wait_for(lambda: self.status()['main_state'] == 'playing', timeout=10)

    def finish_fixture_stream(self):
        # Reach EOF in the silent 90-second mpv fixture. This bypasses the
        # application's seek policy solely to simulate a transport ending.
        with socket.socket(socket.AF_UNIX) as client:
            client.connect(str(self.base/'runtime/sky.lofi/sockets/main.sock'))
            client.sendall((json.dumps({'command':['seek',89,'absolute']}) + '\n').encode())

    def add_builtin_youtube_station(self):
        catalog_path = self.plugin/'stations.json'
        catalog = json.loads(catalog_path.read_text())
        catalog['categories'][0]['stations'].append(dict(id='lofi-girl-test', name='Lofi Girl test', kind='youtube', url=URL))
        catalog_path.write_text(json.dumps(catalog))

    def test_builtin_youtube_station_uses_safe_extractor_and_keeps_voice_and_nature(self):
        self.add_builtin_youtube_station()
        self.action('ui', 'fade', 'off')
        self.action('nature', 'noise-rain', 'on')
        self.action('mix', 'off')
        self.action('start', 'lofi-girl-test')
        self.wait_for(lambda: self.status()['main_state'] == 'playing')
        self.assertEqual(self.status()['category'], 'youtube')
        self.assertTrue(self.status()['voice_available'])
        self.assertFalse(self.status()['mix'])
        self.action('bg', 'voice-changelog')
        self.wait_for(lambda: self.status()['bg_running'] and self.prop('bg', 'pause') is False)
        self.assertTrue(self.status()['mix'])
        bg = self.pid('bg')
        rain = self.pid('nature-noise-rain')
        self.action('pause')
        self.wait_for(lambda: self.prop('bg', 'pause') is True)
        self.action('resume')
        self.wait_for(lambda: self.prop('bg', 'pause') is False)
        self.assertEqual(self.pid('bg'), bg)
        self.assertEqual(self.pid('nature-noise-rain'), rain)
        self.action('mix', 'off')
        self.assertFalse(self.status()['bg_running'])
        self.action('mix', 'on')
        self.wait_for(lambda: self.status()['bg_running'])
        args = json.loads(self.extractor_log.read_text())
        for flag in ('--ignore-config', '--no-plugin-dirs', '--no-remote-components', '--no-playlist'):
            self.assertIn(flag, args)
        self.assertEqual(args[-1], URL)
        if self.backend == 'rust':
            self.assertFalse(self.status()['can_seek'])
            self.assertEqual(self.status()['source_kind'], 'radio')
            self.assertIsNone(self.status()['main_duration'])
            self.assertNotEqual(self.action('seek', '25', check=False).returncode, 0)
        self.assertTrue(any(layer['running'] for layer in self.status()['nature_layers'] if layer['id'] == 'noise-rain'))
        self.action('stop')

    @unittest.skipUnless(os.environ.get('LOFI_TEST_BACKEND') == 'rust', 'Native asynchronous podcast worker')
    def test_builtin_youtube_radio_resolves_podcast_voice_while_playing_and_paused(self):
        self.add_builtin_youtube_station()
        self.action('mix', 'off')
        catalog_path = self.plugin/'stations.json'
        catalog = json.loads(catalog_path.read_text())
        for category in catalog['categories']:
            for station in category['stations']:
                if station['id'] == 'voice-changelog':
                    station.update(kind='podcast', url='https://podcast.invalid/feed.xml')
        catalog_path.write_text(json.dumps(catalog))
        # Restart the private daemon so the podcast catalog is loaded before
        # playback. Its real async worker consumes a fresh offline feed cache.
        self.action('shutdown')
        playlist = self.base/'runtime/sky.lofi/feed-voice-changelog.m3u'
        playlist.parent.mkdir(parents=True, exist_ok=True)
        playlist.write_text('#EXTM3U\n' + str(self.base/'tone.wav') + '\n')
        self.action('start', 'lofi-girl-test')
        self.wait_for(lambda: self.status()['main_state'] == 'playing')
        self.action('bg', 'voice-changelog')
        self.wait_for(lambda: self.status()['bg_running']
                      and self.prop('bg', 'time-pos') >= 0
                      and self.prop('bg', 'pause') is False)
        state = self.status()
        self.assertTrue(state['voice_available'])
        self.assertTrue(state['mix'])
        self.assertTrue(state['bg_running'])
        self.assertEqual(state['bg_station'], 'voice-changelog')
        self.assertEqual(state['bg_error'], '')
        self.assertEqual(playlist.read_text(), '#EXTM3U\n' + str(self.base/'tone.wav') + '\n')
        original_bg = self.pid('bg')

        # Reselecting while paused must start the newly resolved podcast in
        # the existing paused mode, rather than dropping the async result.
        self.action('pause')
        self.action('bg', 'voice-changelog')
        self.wait_for(lambda: self.status()['bg_running']
                      and self.prop('bg', 'time-pos') >= 0
                      and self.prop('bg', 'pause') is True)
        state = self.status()
        self.assertTrue(state['voice_available'])
        self.assertTrue(state['mix'])
        self.assertTrue(state['bg_running'])
        self.assertTrue(state['paused'])
        self.assertEqual(state['bg_error'], '')
        self.assertNotEqual(self.pid('bg'), original_bg)
        paused_bg = self.pid('bg')
        self.action('resume')
        self.wait_for(lambda: self.prop('bg', 'pause') is False)
        self.assertEqual(self.pid('bg'), paused_bg)

    def test_switching_between_builtin_radio_and_saved_youtube_preserves_voice_choice(self):
        self.add_builtin_youtube_station()
        self.action('nature', 'noise-rain', 'on')
        self.action('bg', 'voice-changelog')
        self.action('start', 'lofi-girl-test')
        self.wait_for(lambda: self.status()['main_state'] == 'playing' and self.status()['bg_running'])
        rain = self.pid('nature-noise-rain')
        self.start_video()
        state = self.status()
        self.assertFalse(state['voice_available'])
        self.assertFalse(state['mix'])
        self.assertFalse(state['bg_running'])
        self.assertEqual(state['bg_station'], 'voice-changelog')
        self.assertEqual(self.pid('nature-noise-rain'), rain)
        self.action('mix', 'on')
        self.assertFalse(self.status()['bg_running'])
        self.action('start', 'lofi-girl-test')
        self.wait_for(lambda: self.status()['main_state'] == 'playing' and self.status()['bg_running'])
        state = self.status()
        self.assertTrue(state['voice_available'])
        self.assertTrue(state['mix'])
        self.assertEqual(state['bg_station'], 'voice-changelog')
        self.assertEqual(self.pid('nature-noise-rain'), rain)

    def test_save_reopen_deduplicate_and_remove_without_playback(self):
        self.action('youtube-add', URL, 'Long conversation')
        self.action('youtube-add', 'https://youtu.be/BaW_jenozKc')
        state = self.status()
        self.assertEqual(len(state['youtube_entries']), 1)
        self.assertEqual(state['youtube_entries'][0]['name'], 'Long conversation')
        self.assertFalse(state['running'])
        self.assertFalse(self.extractor_log.exists())
        self.action('youtube-remove', ID)
        self.assertEqual(self.status()['youtube_entries'], [])

    def test_audio_resume_seek_and_nature_are_independent(self):
        self.action('nature', 'noise-rain', 'on')
        self.start_video()
        state = self.status()
        self.assertEqual(state['category'], 'youtube')
        if self.backend == 'rust':
            self.wait_for(lambda: self.status()['can_seek'])
            self.assertGreater(self.status()['main_duration'], 0)
            self.assertEqual(self.status()['source_kind'], 'recording')
            self.assertEqual(self.status()['category_name'], 'YouTube')
        self.assertFalse(state['bg_running'])
        self.assertTrue(state['noise_running'])
        rain = self.pid('nature-noise-rain')
        args = json.loads(self.extractor_log.read_text())
        for flag in ('--ignore-config', '--no-plugin-dirs', '--no-remote-components', '--no-playlist'):
            self.assertIn(flag, args)
        self.assertEqual(args[-1], URL)
        self.action('seek', '25')
        self.wait_for(lambda: self.prop('main', 'time-pos') >= 24)
        self.action('pause')
        self.assertTrue(self.prop('main', 'pause'))
        self.action('stop')
        bookmark = self.status()['youtube_entries'][0]['position']
        self.assertGreater(bookmark, 24)
        self.assertEqual(self.status()['youtube_entries'][0]['name'], 'Offline test conversation')
        self.action('play')
        self.wait_for(lambda: self.status()['main_state'] == 'playing', timeout=10)
        self.assertGreater(self.prop('main', 'time-pos'), 24)
        self.action('start', 'lofi-kalizo')
        self.assertEqual(self.status()['category'], 'lofi')
        self.assertTrue(self.status()['bg_running'])
        self.assertTrue(self.status()['noise_running'])

    @unittest.skipUnless(os.environ.get('LOFI_TEST_BACKEND') == 'rust', 'Native capability policy')
    def test_radio_duration_does_not_enable_seek_or_mpris_timeline(self):
        self.action('start', 'lofi-kalizo')
        self.wait_for(lambda: self.status()['main_state'] == 'playing')
        self.assertGreater(self.prop('main', 'duration'), 0)
        self.assertTrue(self.prop('main', 'seekable'))
        state = self.status()
        self.assertFalse(state['can_seek'])
        self.assertIsNone(state['main_duration'])
        result = self.action('seek', '25', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('live radio', result.stderr)
        reply = subprocess.run(['gdbus', 'call', '--session', '--dest', 'org.mpris.MediaPlayer2.sky.lofi',
            '--object-path', '/org/mpris/MediaPlayer2', '--method', 'org.freedesktop.DBus.Properties.Get',
            'org.mpris.MediaPlayer2.Player', 'CanSeek'], env=self.env, capture_output=True, text=True, check=True)
        self.assertIn('false', reply.stdout)
        self.finish_fixture_stream()
        self.wait_for(lambda: self.status()['main_state'] == 'reconnecting')
        self.assertNotEqual(self.status()['main_state'], 'ended')

    @unittest.skipUnless(os.environ.get('LOFI_TEST_BACKEND') == 'rust', 'Native capability policy')
    def test_saved_live_youtube_has_no_recording_controls(self):
        self.env['LOFI_TEST_EXTRACTOR_LIVE'] = '1'
        self.action('shutdown')
        self.start_video()
        self.wait_for(lambda: self.status()['main_state'] == 'playing')
        self.assertFalse(self.status()['can_seek'])
        self.assertEqual(self.status()['source_kind'], 'live')
        self.assertIsNone(self.status()['main_duration'])
        self.assertNotEqual(self.action('seek', '25', check=False).returncode, 0)
        # Simulate a live transport ending through mpv's private fixture IPC.
        # Application seek remains forbidden; this event must reconnect, never Replay.
        self.finish_fixture_stream()
        self.wait_for(lambda: self.status()['main_state'] == 'reconnecting', timeout=8)
        self.assertNotEqual(self.status()['main_state'], 'ended')

    @unittest.skipUnless(os.environ.get('LOFI_TEST_BACKEND') == 'rust', 'Native capability policy')
    def test_unknown_saved_source_does_not_guess_recording_from_duration(self):
        self.env['LOFI_TEST_EXTRACTOR_UNKNOWN'] = '1'
        self.action('shutdown')
        self.start_video()
        self.assertGreater(self.prop('main', 'duration'), 0)
        self.assertFalse(self.status()['can_seek'])
        self.assertEqual(self.status()['source_kind'], 'unknown')
        self.assertIsNone(self.status()['main_duration'])

    def test_end_does_not_trigger_radio_recovery_and_can_replay(self):
        self.start_video()
        self.action('seek', '89')
        self.wait_for(lambda: self.status()['main_state'] == 'ended', timeout=8)
        self.assertEqual(self.status()['retry_in'], 0)
        self.assertEqual(self.status()['youtube_entries'][0]['position'], 0)
        self.action('toggle')
        self.wait_for(lambda: self.status()['main_state'] == 'playing', timeout=10)
        self.assertLess(self.prop('main', 'time-pos'), 10)

    def test_seek_from_end_resumes_playback(self):
        self.start_video()
        self.action('seek', '89')
        self.wait_for(lambda: self.status()['main_state'] == 'ended', timeout=8)
        self.action('seek', '10')
        self.wait_for(lambda: self.prop('main', 'time-pos') > 11)
        self.assertFalse(self.prop('main', 'pause'))

    def test_stop_cancels_slow_extraction(self):
        self.env['LOFI_TEST_EXTRACTOR_DELAY'] = '30'
        self.env['LOFI_TEST_EXTRACTOR_TREE'] = '3'
        if self.backend == 'rust':
            self.action('shutdown')
        self.action('youtube-add', URL)
        before = time.monotonic()
        self.action('start', ID)
        self.assertLess(time.monotonic() - before, 2)
        self.wait_for(lambda: self.helper_pid.exists() and (self.tree_pids/'0').exists())
        helper_handle = os.pidfd_open(int(self.helper_pid.read_text()))
        self.addCleanup(os.close, helper_handle)
        descendants = []
        for path in self.tree_pids.iterdir():
            descriptor = os.pidfd_open(int(path.read_text()))
            descendants.append(descriptor)
            def cleanup(handle=descriptor):
                if not __import__('select').select([handle], [], [], 0)[0]:
                    signal.pidfd_send_signal(handle, signal.SIGKILL)
                os.close(handle)
            self.addCleanup(cleanup)
        decoy = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
        self.addCleanup(lambda: (decoy.kill() if decoy.poll() is None else None, decoy.wait()))
        pid = int(self.extractor_pid.read_text())
        import select
        handle = os.pidfd_open(pid)
        self.addCleanup(os.close, handle)
        before = time.monotonic()
        self.action('stop')
        self.assertLess(time.monotonic() - before, 2)
        self.assertTrue(select.select([handle], [], [], 3)[0], 'Extractor survived Stop')
        self.assertTrue(select.select([helper_handle], [], [], 3)[0], 'Extractor helper survived Stop')
        for descriptor in descendants:
            self.assertTrue(select.select([descriptor], [], [], 3)[0], 'Nested extractor descendant survived Stop')
        self.assertIsNone(decoy.poll(), 'Unrelated process was terminated')

    def test_remove_current_video_does_not_start_radio(self):
        self.start_video()
        self.action('youtube-remove', ID)
        self.assertFalse(self.status()['main_running'])
        self.assertEqual(self.status()['youtube_entries'], [])
