"""Recovery and nature-mixer regressions; local audio and deterministic retry time."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import player_test

# Importing the controller must not generate files inside the watched plugin.
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lofi_backend as backend


class RecoveryIntegrationTest(unittest.TestCase):
    # Reuse the isolated real-mpv fixture, without inheriting its test methods.
    setUp = player_test.PlayerTest.setUp
    tearDown = player_test.PlayerTest.tearDown
    action = player_test.PlayerTest.action
    status = player_test.PlayerTest.status
    channel = player_test.PlayerTest.channel
    pid = player_test.PlayerTest.pid
    prop = player_test.PlayerTest.prop

    def wait_for(self, predicate, timeout=7):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.05)
        self.assertTrue(predicate(), 'Playback did not reach the expected state')

    def wait_volume(self, channel, expected):
        self.wait_for(lambda: abs(self.prop(channel, 'volume') - expected) < .1, 3)

    def wait_retry(self):
        self.wait_for(lambda: self.status()['retry_in'] > 0)

    def assert_no_music_for(self, seconds=3.2):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            self.assertFalse(self.status()['main_running'])
            time.sleep(.1)

    def test_reconnect_preserves_voice_and_each_nature_process(self):
        self.action('play')
        self.action('nature', 'noise-rain', 'on')
        self.action('nature', 'noise-wind', 'on')
        self.action('vol', 'noise-rain', '50')
        self.action('vol', 'noise-wind', '80')
        self.action('vol', 'master', '50')
        channels = ('bg', 'nature-noise-rain', 'nature-noise-wind')
        previous = {channel: self.pid(channel) for channel in channels}
        main = self.pid('main')
        os.kill(int(main), signal.SIGTERM)
        self.wait_retry()
        self.wait_for(lambda: self.status()['main_state'] == 'playing'
                      and self.pid('main') != main)
        for channel, pid in previous.items():
            self.assertEqual(self.pid(channel), pid)
            self.assertFalse(self.prop(channel, 'pause'))
        self.wait_volume('main', 32.5)
        self.wait_volume('bg', 10)
        self.wait_volume('nature-noise-rain', 25)
        self.wait_volume('nature-noise-wind', 40)

    def test_pause_cancels_retry_even_without_other_channels(self):
        self.action('bg', 'off')
        self.action('play')
        os.kill(int(self.pid('main')), signal.SIGTERM)
        self.wait_retry()
        self.action('pause')
        self.assertTrue(self.status()['paused'])
        self.assert_no_music_for()
        self.assertEqual(self.status()['retry_in'], 0)
        self.action('resume')
        self.wait_for(lambda: self.status()['main_state'] == 'playing')
        self.assertFalse(self.status()['paused'])

    def test_stop_cancels_retry_and_does_not_restart_from_status(self):
        self.action('play')
        self.action('nature', 'noise-rain', 'on')
        os.kill(int(self.pid('main')), signal.SIGTERM)
        self.wait_retry()
        self.action('stop')
        self.assert_no_music_for()
        state = self.status()
        self.assertFalse(state['running'])
        self.assertFalse(state['bg_running'])
        self.assertFalse(state['noise_running'])
        self.assertEqual(state['main_state'], 'stopped')
        self.assertEqual(state['retry_in'], 0)

    def test_new_station_replaces_pending_retry(self):
        self.action('play')
        os.kill(int(self.pid('main')), signal.SIGTERM)
        self.wait_retry()
        self.action('start', 'lofi-kalizo')
        self.wait_for(lambda: self.status()['main_state'] == 'playing')
        current = self.pid('main')
        deadline = time.monotonic() + 3.2
        while time.monotonic() < deadline:
            state = self.status()
            self.assertEqual(state['station'], 'lofi-kalizo')
            self.assertEqual(self.pid('main'), current)
            time.sleep(.1)
        self.assertEqual(self.status()['retry_attempt'], 0)

    def remove_music_station(self, id):
        path = self.plugin/'stations.json'
        catalog = json.loads(path.read_text())
        music = next(category for category in catalog['categories'] if category['id'] == 'lofi')
        music['stations'] = [station for station in music['stations'] if station['id'] != id]
        replacement = path.with_suffix('.new')
        replacement.write_text(json.dumps(catalog))
        replacement.replace(path)

    def test_removed_playing_station_replaces_audio_without_restarting_other_layers(self):
        self.action('start', 'lofi-kalizo')
        self.action('nature', 'noise-rain', 'on')
        self.action('nature', 'noise-wind', 'on')
        self.action('vol', 'main', '44')
        self.action('vol', 'master', '50')
        self.action('vol', 'noise-rain', '72')
        self.wait_for(lambda: self.status()['main_state'] == 'playing')
        previous = {channel: self.pid(channel)
                    for channel in ('main', 'bg', 'nature-noise-rain', 'nature-noise-wind')}
        self.remove_music_station('lofi-kalizo')
        self.wait_for(lambda: self.status()['station'] == 'lofi-lilo'
                      and self.status()['main_state'] == 'playing')
        self.assertNotEqual(self.pid('main'), previous['main'])
        self.assertFalse(self.status()['paused'])
        self.assertEqual(self.status()['retry_attempt'], 0)
        self.wait_volume('main', 22)
        self.wait_volume('nature-noise-rain', 36)
        for channel in ('bg', 'nature-noise-rain', 'nature-noise-wind'):
            self.assertEqual(self.pid(channel), previous[channel])
            self.assertFalse(self.prop(channel, 'pause'))
        settings = json.loads((self.base/'state/sky.lofi/settings.json').read_text())
        self.assertEqual(settings['defaultStation'], 'lofi-lilo')

    def test_removed_paused_station_waits_for_resume_and_keeps_valid_default(self):
        self.action('start', 'lofi-kalizo')
        self.action('nature', 'noise-rain', 'on')
        self.action('default', 'lofi-purrple-cat')
        self.action('pause')
        previous = {channel: self.pid(channel) for channel in ('main', 'bg', 'nature-noise-rain')}
        self.remove_music_station('lofi-kalizo')
        state = self.status()
        self.assertTrue(state['paused'])
        self.assertEqual(state['station'], 'lofi-purrple-cat')
        self.assertEqual(state['retry_in'], 0)
        self.assert_no_music_for()
        for channel in ('bg', 'nature-noise-rain'):
            self.assertEqual(self.pid(channel), previous[channel])
            self.assertTrue(self.prop(channel, 'pause'))
        self.action('resume')
        self.wait_for(lambda: self.status()['main_state'] == 'playing')
        self.assertEqual(self.status()['station'], 'lofi-purrple-cat')
        self.assertNotEqual(self.pid('main'), previous['main'])
        for channel in ('bg', 'nature-noise-rain'):
            self.assertEqual(self.pid(channel), previous[channel])
            self.assertFalse(self.prop(channel, 'pause'))

    def test_removed_stopped_station_does_not_start_audio(self):
        self.action('start', 'lofi-kalizo')
        self.action('nature', 'noise-rain', 'on')
        self.action('stop')
        self.remove_music_station('lofi-kalizo')
        self.assert_no_music_for()
        state = self.status()
        self.assertEqual(state['station'], 'lofi-lilo')
        self.assertEqual(state['main_state'], 'stopped')
        self.assertFalse(state['running'])
        self.assertFalse(state['bg_running'])
        self.assertFalse(state['noise_running'])
        self.action('play')
        self.wait_for(lambda: self.status()['main_state'] == 'playing')
        self.assertEqual(self.status()['station'], 'lofi-lilo')

    def test_layers_keep_individual_balance_under_master_and_voxtype(self):
        self.env['XDG_CONFIG_HOME'] = str(self.base/'config')
        vox = self.base/'runtime/voxtype'
        vox.mkdir()
        (vox/'pid').write_text(str(os.getpid()))
        (vox/'state').write_text('idle')
        self.action('play')
        self.action('vol', 'noise-rain', '50')
        self.action('vol', 'noise-wind', '80')
        self.action('nature', 'noise-rain', 'on')
        self.action('nature', 'noise-wind', 'on')
        self.action('vol', 'master', '50')
        levels = {'main': 32.5, 'bg': 10, 'nature-noise-rain': 25, 'nature-noise-wind': 40}
        for channel, expected in levels.items():
            self.wait_volume(channel, expected)
        (vox/'state').write_text('recording')
        for channel, expected in levels.items():
            self.wait_volume(channel, expected * .2)
        self.action('vol', 'master', '0')
        for channel in levels:
            self.wait_volume(channel, 0)
        self.action('nature', 'noise-rain', 'off')
        self.action('vol', 'master', '50')
        (vox/'state').write_text('idle')
        self.wait_volume('nature-noise-wind', 40)
        self.action('stop')
        self.action('play')
        layers = {entry['id']: entry for entry in self.status()['nature_layers']}
        self.assertFalse(layers['noise-rain']['enabled'])
        self.assertFalse(layers['noise-rain']['running'])
        self.assertTrue(layers['noise-wind']['running'])
        self.assertEqual(layers['noise-rain']['volume'], 50)
        self.assertEqual(layers['noise-wind']['volume'], 80)
        self.wait_volume('nature-noise-wind', 40)

    def test_slow_podcast_fetch_does_not_block_pause_or_stop(self):
        catalog_path = self.plugin/'stations.json'
        catalog = json.loads(catalog_path.read_text())
        for category in catalog['categories']:
            for station in category['stations']:
                if station['id'] == 'voice-changelog':
                    station['kind'] = 'podcast'
        catalog_path.write_text(json.dumps(catalog))
        entered = self.base/'feed-entered'
        release = self.base/'feed-release'
        (self.plugin/'lofi_feed.py').write_text(
            "import time\nfrom pathlib import Path\n"
            "def resolve(url, destination):\n"
            f"    Path({str(entered)!r}).touch()\n"
            "    deadline = time.monotonic() + 8\n"
            f"    while not Path({str(release)!r}).exists() and time.monotonic() < deadline:\n"
            "        time.sleep(.01)\n"
            f"    Path(destination).write_text({str(self.base/'tone.wav')!r} + '\\n')\n"
        )
        self.action('bg', 'off')
        self.action('play')
        started = time.monotonic()
        self.action('bg', 'voice-changelog')
        self.assertLess(time.monotonic() - started, 2)
        self.wait_for(entered.exists, 3)
        feed_handle = os.pidfd_open(int(self.pid('feed')))
        self.addCleanup(os.close, feed_handle)
        started = time.monotonic()
        self.action('pause')
        self.assertLess(time.monotonic() - started, 2)
        self.assertTrue(self.status()['paused'])
        started = time.monotonic()
        self.action('stop')
        self.assertLess(time.monotonic() - started, 2)
        release.touch()
        import select
        self.assertTrue(select.select([feed_handle], [], [], 1)[0], 'Feed worker must exit on Stop')
        self.assertFalse(list((self.base/'runtime/sky.lofi').glob('*.m3u')))
        self.assertFalse(self.status()['bg_running'])
        self.assertFalse((self.base/'runtime/sky.lofi/feed.pid').exists())

    def test_update_replaces_old_worker_without_restarting_audio(self):
        self.action('play')
        self.action('nature', 'noise-rain', 'on')
        channels = ('main', 'bg', 'nature-noise-rain')
        previous = {channel: self.pid(channel) for channel in channels}
        worker = self.pid('volume')
        handle = os.pidfd_open(int(worker))
        self.addCleanup(os.close, handle)
        controller = self.plugin/'lofi_backend.py'
        controller.write_text(controller.read_text() + '\n# Simulate a controller update.\n')
        self.assertTrue(self.status()['running'])
        self.assertNotEqual(self.pid('volume'), worker)
        import select
        self.assertTrue(select.select([handle], [], [], 1)[0])
        for channel in channels:
            self.assertEqual(self.pid(channel), previous[channel])
        self.action('vol', 'master', '50')
        self.wait_volume('main', 32.5)

    def test_legacy_nature_selection_migrates_once_with_same_volume(self):
        path = self.base/'state/sky.lofi/settings.json'
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({'noiseStation': 'noise-rain', 'noiseVolume': 37,
                                    'mainVolume': 44, 'masterVolume': 60, 'mix': False}))
        state = self.status()
        self.assertEqual(state['main_volume'], 44)
        layers = {entry['id']: entry for entry in state['nature_layers']}
        self.assertTrue(layers['noise-rain']['enabled'])
        self.assertEqual(layers['noise-rain']['volume'], 37)
        self.action('play')
        self.wait_volume('nature-noise-rain', 22.2)
        self.action('nature', 'noise-rain', 'off')
        self.action('stop')
        self.action('play')
        self.assertFalse(self.status()['noise_running'])
        # Opening again must never re-enable rain or multiply its volume twice.
        saved = json.loads(path.read_text())
        self.assertEqual(saved['natureMixVersion'], 2)
        self.assertEqual(saved['natureLayers']['noise-rain']['volume'], 37)
        self.assertFalse(saved['natureLayers']['noise-rain']['enabled'])


    def test_layered_settings_migrate_without_changing_active_or_saved_loudness(self):
        path = self.base/'state/sky.lofi/settings.json'
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({
            'natureVolume': 47, 'masterVolume': 60, 'mix': False,
            'natureLayers': {
                'noise-rain': {'enabled': True, 'volume': 100},
                'noise-wind': {'enabled': False, 'volume': 70},
                'noise-birds': {'enabled': True, 'volume': 0},
            },
        }))
        self.action('play')
        layers = {entry['id']: entry for entry in self.status()['nature_layers']}
        self.assertEqual(layers['noise-rain']['volume'], 47)
        self.assertAlmostEqual(layers['noise-wind']['volume'], 32.9)
        self.assertFalse(layers['noise-wind']['enabled'])
        self.assertEqual(layers['noise-birds']['volume'], 0)
        self.wait_volume('nature-noise-rain', 28.2)
        self.wait_volume('nature-noise-birds', 0)
        self.action('nature', 'noise-wind', 'on')
        self.wait_volume('nature-noise-wind', 19.74)
        # Repeated reads/restarts cannot bake the removed group multiplier in again.
        self.status()
        self.action('stop')
        self.action('play')
        self.wait_volume('nature-noise-rain', 28.2)
        self.wait_volume('nature-noise-wind', 19.74)
        saved = json.loads(path.read_text())
        self.assertEqual(saved['natureMixVersion'], 2)
        self.assertAlmostEqual(saved['natureLayers']['noise-wind']['volume'], 32.9)
        # A direct slider reaches the requested level without the old 47% ceiling.
        self.action('vol', 'noise-rain', '90')
        self.wait_volume('nature-noise-rain', 54)
        self.wait_volume('nature-noise-wind', 19.74)
        self.action('nature', 'noise-storm', 'on')
        self.wait_volume('nature-noise-storm', 15)

    def test_legacy_nature_volume_command_sets_only_enabled_layers_directly(self):
        self.action('vol', 'noise-birds', '72')
        self.action('nature', 'noise-rain', 'on')
        self.action('nature', 'noise-wind', 'on')
        self.action('play')
        self.action('vol', 'nature', '30')
        self.wait_volume('nature-noise-rain', 30)
        self.wait_volume('nature-noise-wind', 30)
        layers = {entry['id']: entry for entry in self.status()['nature_layers']}
        self.assertEqual(layers['noise-birds']['volume'], 72)
        self.assertFalse(layers['noise-birds']['enabled'])
        self.action('vol', 'noise-rain', '80')
        self.wait_volume('nature-noise-rain', 80)
        self.wait_volume('nature-noise-wind', 30)
        self.action('nature', 'noise-birds', 'on')
        self.wait_volume('nature-noise-birds', 72)


class RecoveryScheduleTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        env = mock.patch.dict(os.environ, XDG_RUNTIME_DIR=str(base/'runtime'),
                              XDG_STATE_HOME=str(base/'state'), XDG_CONFIG_HOME=str(base/'config'))
        env.start()
        self.addCleanup(env.stop)
        self.now = 100.0
        clock = mock.patch.object(backend.time, 'monotonic', side_effect=lambda: self.now)
        clock.start()
        self.addCleanup(clock.stop)
        self.player = backend.Player()
        self.addCleanup(self.player.lock.close)
        self.player.acquire()
        self.addCleanup(self.player.release)
        self.player.session.update(mode='playing', station='lofi-lilo', attempts=0,
                                   started=self.now, retry_due=0)
        self.main_alive = False
        self.position = None
        self.player.alive = mock.Mock(side_effect=lambda channel: channel == 'main' and self.main_alive)
        self.player.spawn = mock.Mock()
        self.player.stop_channel = mock.Mock(side_effect=self.stop_channel)
        commands = mock.patch.object(backend, 'ipc', side_effect=lambda path, command: self.position)
        commands.start()
        self.addCleanup(commands.stop)

    def stop_channel(self, channel):
        if channel == 'main':
            self.main_alive = False

    def test_exhausted_retries_follow_backoff_and_do_not_restart_forever(self):
        for attempt, delay in enumerate(backend.RETRY_DELAYS):
            self.player.maintain()
            due = self.now + delay
            self.assertEqual(self.player.session['retry_due'], due)
            self.now = due - .01
            self.player.maintain()
            self.assertEqual(self.player.spawn.call_count, attempt)
            self.now = due
            self.player.maintain()
            self.assertEqual(self.player.spawn.call_count, attempt + 1)
            self.assertEqual(self.player.session['attempts'], attempt + 1)
        self.player.maintain()
        self.now += 10000
        self.player.maintain()
        self.assertEqual(self.player.spawn.call_count, len(backend.RETRY_DELAYS))
        self.assertEqual(self.player.session['retry_due'], 0)
        self.assertEqual(self.player.status()['main_state'], 'failed')

    def test_retry_budget_resets_only_after_stable_playback(self):
        self.main_alive = True
        self.position = 1
        self.player.session['attempts'] = 3
        self.player.maintain()
        self.assertEqual(self.player.session['attempts'], 3)
        self.now += backend.STABLE_SECONDS - 1
        self.position += 1
        self.player.maintain()
        self.assertEqual(self.player.session['attempts'], 3)
        self.now += 1
        self.position += 1
        self.player.maintain()
        self.assertEqual(self.player.session['attempts'], 0)
        self.player.spawn.assert_not_called()

    def test_connecting_process_times_out_and_schedules_retry(self):
        self.main_alive = True
        self.player.maintain()
        self.assertEqual(self.player.session['retry_due'], 0)
        self.now += backend.CONNECT_TIMEOUT
        self.player.maintain()
        self.player.stop_channel.assert_called_once_with('main')
        self.assertEqual(self.player.session['retry_due'], self.now + backend.RETRY_DELAYS[0])

    def test_new_attempt_does_not_inherit_previous_stall_timestamp(self):
        self.player.session.update(last_position=0, progress_at=self.now - 100, attempts=2)
        self.player.start_music(reset=False)
        self.main_alive = True
        self.position = 0
        self.player.maintain()
        self.player.stop_channel.assert_not_called()
        self.assertEqual(self.player.session['retry_due'], 0)

    def test_late_feed_result_cannot_override_stop_or_new_voice_choice(self):
        for mode, station, token in [('stopped', 'voice-changelog', 'old'),
                                     ('playing', 'voice-linux-unplugged', 'old'),
                                     ('playing', 'voice-changelog', 'new')]:
            with self.subTest(mode=mode, station=station, token=token):
                self.player.settings.update(mix=True, bgStation=station)
                self.player.session.update(mode=mode, feed_token=token)
                self.player.save()
                self.player.release()
                self.player.spawn.reset_mock()
                with mock.patch.object(backend, 'resolve_playlist'):
                    backend.resolve_feed(self.player, 'voice-changelog', 'old')
                self.player.spawn.assert_not_called()

    def test_worker_refreshes_catalog_before_retry(self):
        catalog_dir = Path(self.temp.name)/'new-catalog'
        catalog_dir.mkdir()
        catalog = json.loads((backend.ROOT/'stations.json').read_text())
        music = next(c for c in catalog['categories'] if c['id'] == 'lofi')
        music['stations'][0]['url'] = 'https://example.invalid/updated-stream'
        (catalog_dir/'stations.json').write_text(json.dumps(catalog))
        self.player.save()
        self.player.release()
        with mock.patch.object(backend, 'ROOT', catalog_dir):
            self.player.acquire()
            self.player.start_music(reset=False)
        self.assertEqual(self.player.spawn.call_args.args[1], 'https://example.invalid/updated-stream')

    def test_explicit_empty_layers_do_not_migrate_legacy_selection_again(self):
        self.player.settings.pop('natureMixVersion', None)
        self.player.settings.update(noiseStation='noise-rain', noiseVolume=80,
                                    natureLayers={}, natureVolume=31)
        self.player.save()
        self.player.release()
        self.player.acquire()
        self.assertEqual(self.player.settings['natureLayers'], {})
        self.assertEqual(self.player.settings['natureMixVersion'], 2)


if __name__ == '__main__':
    unittest.main()
