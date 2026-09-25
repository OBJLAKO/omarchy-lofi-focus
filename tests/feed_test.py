"""Feed worker extraction preserves playlist parsing and cache fallback."""
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lofi_feed


class FeedTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.cache = Path(self.temp.name)/'episodes.m3u'

    def test_feed_filters_enclosures_and_caps_playlist(self):
        xml = '<rss><channel>' + ''.join(
            f'<item><enclosure url="https://example.test/{i}.mp3"/></item>' for i in range(15))
        xml = xml.replace('<channel>', '<channel><item><enclosure url="file:///tmp/not-a-stream"/></item>')
        xml += '</channel></rss>'
        with mock.patch.object(lofi_feed.urllib.request, 'urlopen', return_value=io.BytesIO(xml.encode())):
            self.assertEqual(lofi_feed.resolve('https://example.test/feed', self.cache), self.cache)
        self.assertEqual(self.cache.read_text().splitlines(), ['#EXTM3U'] + [f'https://example.test/{i}.mp3' for i in range(12)])
        with mock.patch.object(lofi_feed.urllib.request, 'urlopen') as request:
            lofi_feed.resolve('https://example.test/feed', self.cache)
            request.assert_not_called()

    def test_unavailable_feed_uses_existing_stale_cache(self):
        self.cache.write_text('#EXTM3U\nhttps://example.test/previous.mp3\n')
        os.utime(self.cache, (0, 0))
        before = self.cache.read_bytes()
        with mock.patch.object(lofi_feed.urllib.request, 'urlopen', side_effect=OSError('offline')):
            self.assertEqual(lofi_feed.resolve('https://example.test/feed', self.cache), self.cache)
        self.assertEqual(self.cache.read_bytes(), before)

    def test_unavailable_feed_without_cache_fails(self):
        with mock.patch.object(lofi_feed.urllib.request, 'urlopen', side_effect=OSError('offline')):
            with self.assertRaisesRegex(ValueError, 'Podcast unavailable'):
                lofi_feed.resolve('https://example.test/feed', self.cache)
        self.assertFalse(self.cache.exists())


if __name__ == '__main__':
    unittest.main()
