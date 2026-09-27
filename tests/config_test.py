"""Corrupt local preferences must not disable transport or the volume worker."""
import json
import tempfile
from pathlib import Path
import unittest
from unittest import mock
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lofi_config import read_json, preferences, session_state
import player_test


class ConfigTest(unittest.TestCase):
    def test_bounded_and_typed_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'settings.json'
            for text in ('null', '[]', '42', '"text"', '{bad', '[' * 2000, ' ' * (1024 * 1024 + 1)):
                path.write_text(text)
                self.assertEqual(read_json(path, {}), {})

    def test_transient_state_types(self):
        self.assertEqual(session_state({'mode': []}), {})
        state = session_state(dict(mode='playing', station=[], retry_due='bad', attempts=None, pending={}))
        self.assertEqual(state['station'], '')
        self.assertEqual(state['retry_due'], 0)
        self.assertEqual(state['attempts'], 0)
        self.assertIsNone(state['pending'])

    def test_ipc_rejects_excessive_or_non_object_responses(self):
        from lofi_backend import ipc
        for line in ('[]\n', 'x' * (1024 * 1024 + 1), '{"event":"tick"}\n'):
            with mock.patch('lofi_backend.socket.socket') as factory:
                stream = factory.return_value.__enter__.return_value.makefile.return_value.__enter__.return_value
                stream.readline.return_value = line
                self.assertIsNone(ipc(Path('/unused'), ['get_property', 'volume']))
                self.assertLessEqual(stream.readline.call_count, 64)

    def test_nested_preferences(self):
        result = preferences(dict(defaultStation=[], bgStation={}, mainVolume='NaN',
                                  masterVolume='bad', duckLevel=None, mix='false',
                                  natureLayers={'noise-rain': [], '../escape': {},
                                                'noise-wind': {'volume': 'inf', 'enabled': True}}))
        self.assertEqual(result['mainVolume'], 65)
        self.assertEqual(result['masterVolume'], 100)
        self.assertNotIn('defaultStation', result)
        self.assertNotIn('mix', result)
        self.assertEqual(result['natureLayers'], {'noise-wind': {'volume': 25, 'enabled': True}})


class ConfigRecoveryTest(unittest.TestCase):
    setUp = player_test.PlayerTest.setUp
    tearDown = player_test.PlayerTest.tearDown
    action = player_test.PlayerTest.action
    status = player_test.PlayerTest.status

    def test_corrupt_preferences_and_empty_catalog_leave_stop_usable(self):
        self.action('status')
        settings = self.base/'state/sky.lofi/settings.json'
        for value in ([], None, {'defaultStation': [], 'natureLayers': {'noise-rain': None}, 'masterVolume': 'bad'}):
            settings.write_text(json.dumps(value))
            self.assertEqual(self.status()['master_volume'], 100)
            self.action('stop')
        (self.plugin/'stations.json').write_text('{"categories": [null, {"id":"lofi","name":"Music","stations":[]}]}')
        self.action('stop')
        self.assertEqual(self.status()['count'], 0)
        self.assertNotEqual(self.action('next', check=False).returncode, 0)
