"""3.5 scenes and local Rust mixer, using isolated output and state."""
import json
import os
import shutil
import time
import unittest
from player_test import PlayerTest

NATIVE = os.environ.get('LOFI_TEST_BACKEND') == 'rust'


@unittest.skipUnless(NATIVE, 'Select the Rust backend for 3.5 checks')
class SpaceTest(PlayerTest):
    def setUp(self):
        super().setUp()
        self.env['SKYLOFI_NATURE_ENGINE'] = 'rust'
        self.env['SKYLOFI_AUDIO_OUTPUT'] = 'mock'

    # Inherited transport regressions inspect mpv nature sockets. Run only the
    # new cases here; those legacy cases retain their separate fixture.
    def test_saved_scene_preserves_master_and_stopped_intent(self):
        self.action('nature', 'noise-rain', 'on')
        self.action('vol', 'noise-rain', '61')
        self.action('layer', 'noise-rain', 'distance', '78')
        self.action('layer', 'noise-rain', 'pan', '-55')
        self.action('wander', 'on')
        self.action('room', 'preset', 'cafe')
        self.action('scene-save', 'Rainy study')
        original = self.status()
        identity = original['scene_id']
        self.assertFalse(original['scene_dirty'])
        self.action('vol', 'master', '13')
        self.assertFalse(self.status()['scene_dirty'])
        self.action('vol', 'noise-rain', '4')
        self.assertTrue(self.status()['scene_dirty'])
        self.action('scene-apply', identity)
        state = self.status()
        self.assertFalse(state['running'])
        self.assertEqual(state['master_volume'], 13)
        self.assertEqual(state['room']['preset'], 'cafe')
        rain = next(l for l in state['nature_layers'] if l['id'] == 'noise-rain')
        self.assertEqual((rain['volume'], rain['distance'], rain['pan']), (61, 78, -55))
        self.assertTrue(state['wander']['enabled'])

    def test_native_mixer_has_no_nature_subprocess_and_preserves_pause(self):
        self.action('ui', 'fade', 'off')
        self.action('nature', 'noise-rain', 'on')
        self.action('nature', 'noise-wind', 'on')
        self.action('play')
        self.wait_for(lambda: all(l['running'] for l in self.status()['nature_layers'] if l['enabled']))
        self.assertEqual(self.status()['nature_engine'], 'rust')
        self.assertFalse((self.base / 'runtime/sky.lofi/nature-noise-rain.pid').exists())
        self.action('scene-save', 'Quiet room')
        identity = self.status()['scene_id']
        self.action('pause')
        self.action('room', 'preset', 'hall')
        self.action('scene-apply', identity)
        self.assertTrue(self.status()['paused'])
        self.action('stop')
        self.assertFalse(any(l['running'] for l in self.status()['nature_layers']))

    def test_living_levels_preserve_saved_faders_and_freeze_on_pause(self):
        self.action('ui', 'fade', 'off')
        self.action('nature', 'noise-rain', 'on')
        self.action('nature', 'noise-wind', 'on')
        self.action('vol', 'noise-rain', '61')
        self.action('vol', 'noise-wind', '45')
        self.action('wander-amount', '100')
        self.action('wander', 'on')
        self.action('scene-save', 'Living rain')
        self.action('play')
        path = self.base / 'state/sky.lofi/settings.json'
        before = path.read_bytes()
        self.wait_for(lambda: any(l['enabled'] and l['effective_volume'] < l['volume'] - 0.001 for l in self.status()['nature_layers']), timeout=4)
        state = self.status()
        self.assertFalse(state['scene_dirty'])
        for layer in state['nature_layers']:
            if layer['enabled']:
                self.assertGreaterEqual(layer['effective_volume'], 0)
                self.assertLessEqual(layer['effective_volume'], layer['volume'])
        self.assertEqual(path.read_bytes(), before)
        self.action('pause')
        paused = {l['id']: l['effective_volume'] for l in self.status()['nature_layers'] if l['enabled']}
        time.sleep(1.2)
        after = {l['id']: l['effective_volume'] for l in self.status()['nature_layers'] if l['enabled']}
        self.assertEqual(paused, after)
        self.action('layer', 'noise-rain', 'living', 'off')
        self.action('resume')
        self.wait_for(lambda: next(l for l in self.status()['nature_layers'] if l['id'] == 'noise-rain')['effective_volume'] == 61, timeout=4)

    def test_invalid_effects_and_scene_reference_are_transactional(self):
        for args in [('layer', 'noise-rain', 'pan', 'nan'), ('layer', 'noise-rain', 'echo', '101'), ('room', 'size', '-1'), ('wander-amount', 'inf'), ('scene-apply', '../../bad')]:
            self.assertNotEqual(self.action(*args, check=False).returncode, 0)
        self.action('nature', 'noise-rain', 'on')
        self.action('scene-save', 'Missing source')
        identity = self.status()['scene_id']
        catalog = json.loads((self.plugin / 'stations.json').read_text())
        for c in catalog['categories']:
            if c['id'] == 'ambience':
                c['stations'] = [s for s in c['stations'] if s['id'] != 'noise-rain']
        (self.plugin / 'stations.json').write_text(json.dumps(catalog))
        self.wait_for(lambda: not any(l['id'] == 'noise-rain' for l in self.status()['nature_layers']))
        before = self.status()['room']
        self.assertNotEqual(self.action('scene-apply', identity, check=False).returncode, 0)
        self.assertEqual(self.status()['room'], before)
        self.assertFalse(self.status()['running'])

    def test_removed_active_catalog_source_is_reconciled(self):
        self.action('ui', 'fade', 'off')
        self.action('nature', 'noise-rain', 'on')
        self.action('play')
        self.wait_for(lambda: any(l['id'] == 'noise-rain' and l['running'] for l in self.status()['nature_layers']))
        catalog = json.loads((self.plugin / 'stations.json').read_text())
        for c in catalog['categories']:
            if c['id'] == 'ambience':
                c['stations'] = [s for s in c['stations'] if s['id'] != 'noise-rain']
        (self.plugin / 'stations.json').write_text(json.dumps(catalog))
        self.wait_for(lambda: not any(l['id'] == 'noise-rain' for l in self.status()['nature_layers']))
        self.action('stop')
        self.assertFalse(any(l['running'] for l in self.status()['nature_layers']))

    def test_import_is_private_validated_and_bundled_files_cannot_be_deleted(self):
        source = self.base / 'a sound.wav'
        shutil.copyfile(self.base / 'tone.wav', source)
        self.action('sound-import', str(source), 'My soft room')
        state = self.status()
        identity = state['imported_sounds'][0]['id']
        metadata = json.loads((self.base / 'state/sky.lofi/settings.json').read_text())['importedSounds'][0]
        stored = self.base / 'state/sky.lofi/sounds' / metadata['file']
        self.assertTrue(stored.is_file())
        self.assertEqual(stored.stat().st_mode & 0o777, 0o600)
        source.unlink()
        self.action('ui', 'fade', 'off')
        self.action('play')
        self.wait_for(lambda: any(l['id'] == identity and l['running'] for l in self.status()['nature_layers']))
        self.assertNotEqual(self.action('sound-remove', 'noise-rain', check=False).returncode, 0)
        self.action('sound-remove', identity)
        self.assertFalse(stored.exists())
        self.assertEqual(self.status()['imported_sounds'], [])
        damaged = self.base / 'damaged.ogg'
        damaged.write_bytes(b'not an audio file')
        self.assertNotEqual(self.action('sound-import', str(damaged), check=False).returncode, 0)
        self.assertEqual(list(stored.parent.iterdir()), [])


# unittest otherwise inherits every old mpv-socket case from PlayerTest.
for _name in list(PlayerTest.__dict__):
    if _name.startswith('test_') and _name not in SpaceTest.__dict__:
        setattr(SpaceTest, _name, None)
