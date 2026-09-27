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
                       ext='wav', protocol='http', duration=90)
        self.extractor_log = self.base/'extractor-args.json'
        self.extractor_pid = self.base/'extractor.pid'
        self.helper_pid = self.base/'helper.pid'
        script = ('#!/usr/bin/env python3\nimport json,os,sys,time,subprocess\nfrom pathlib import Path\n'
                  f'Path({str(self.extractor_log)!r}).write_text(json.dumps(sys.argv[1:]))\n'
                  f'Path({str(self.extractor_pid)!r}).write_text(str(os.getpid()))\n'
                  'if os.environ.get("LOFI_TEST_EXTRACTOR_DELAY"):\n'
                  '    helper = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])\n'
                  f'    Path({str(self.helper_pid)!r}).write_text(str(helper.pid))\n'
                  'time.sleep(float(os.environ.get("LOFI_TEST_EXTRACTOR_DELAY", "0")))\n'
                  f'print({json.dumps(payload)!r})\n')
        (self.bin/'yt-dlp').write_text(script)
        (self.bin/'yt-dlp').chmod(0o755)
        self.action('ui', 'fade', 'off')

    def start_video(self):
        self.action('youtube-add', URL)
        self.action('start', ID)
        self.wait_for(lambda: self.status()['main_state'] == 'playing', timeout=10)

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
        self.action('youtube-add', URL)
        before = time.monotonic()
        self.action('start', ID)
        self.assertLess(time.monotonic() - before, 2)
        self.wait_for(self.helper_pid.exists)
        helper_handle = os.pidfd_open(int(self.helper_pid.read_text()))
        self.addCleanup(os.close, helper_handle)
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
        self.assertIsNone(decoy.poll(), 'Unrelated process was terminated')

    def test_remove_current_video_does_not_start_radio(self):
        self.start_video()
        self.action('youtube-remove', ID)
        self.assertFalse(self.status()['main_running'])
        self.assertEqual(self.status()['youtube_entries'], [])
