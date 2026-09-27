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
        with mock.patch.object(lofi_feed, 'open_feed', return_value=io.BytesIO(xml.encode())):
            self.assertEqual(lofi_feed.resolve('https://example.test/feed', self.cache), self.cache)
        self.assertEqual(self.cache.read_text().splitlines(), ['#EXTM3U'] + [f'https://example.test/{i}.mp3' for i in range(12)])
        with mock.patch.object(lofi_feed, 'open_feed') as request:
            lofi_feed.resolve('https://example.test/feed', self.cache)
            request.assert_not_called()

    def test_unavailable_feed_uses_existing_stale_cache(self):
        self.cache.write_text('#EXTM3U\nhttps://example.test/previous.mp3\n')
        os.utime(self.cache, (0, 0))
        before = self.cache.read_bytes()
        with mock.patch.object(lofi_feed, 'open_feed', side_effect=OSError('offline')):
            self.assertEqual(lofi_feed.resolve('https://example.test/feed', self.cache), self.cache)
        self.assertEqual(self.cache.read_bytes(), before)

    def test_oversized_feed_is_rejected(self):
        with mock.patch.object(lofi_feed, 'MAX_FEED_BYTES', 32):
            with mock.patch.object(lofi_feed, 'open_feed', return_value=io.BytesIO(b'x' * 33)):
                with self.assertRaisesRegex(ValueError, 'too large'):
                    lofi_feed.resolve('https://example.test/feed', self.cache)
        self.assertFalse(self.cache.exists())

    def test_dtd_and_entities_are_rejected_in_utf8_and_utf16(self):
        xml = '<!DOCTYPE rss [<!ENTITY url "https://example.test/a.mp3">]><rss><enclosure url="&url;"/></rss>'
        for encoding in ('utf-8', 'utf-16'):
            with self.subTest(encoding=encoding):
                with mock.patch.object(lofi_feed, 'open_feed', return_value=io.BytesIO(xml.encode(encoding))):
                    with self.assertRaisesRegex(ValueError, 'DTD'):
                        lofi_feed.resolve('https://example.test/feed', self.cache)
        self.assertFalse(self.cache.exists())

    def test_feed_url_and_redirect_reject_unsafe_schemes(self):
        for url in ('file:///etc/passwd', 'http://example.test/rss', 'https:///missing-host',
                    'https://example.test/a\nfile:///tmp/audio', 'https://user:pass@example.test/rss'):
            with self.subTest(url=url):
                self.assertFalse(lofi_feed.https_url(url))
                with self.assertRaises(ValueError):
                    lofi_feed.open_feed(url)
                with self.assertRaises(ValueError):
                    lofi_feed.HTTPSRedirect().redirect_request(None, None, 302, '', {}, url)

    def test_unavailable_feed_without_cache_fails(self):
        with mock.patch.object(lofi_feed, 'open_feed', side_effect=OSError('offline')):
            with self.assertRaisesRegex(ValueError, 'Podcast unavailable'):
                lofi_feed.resolve('https://example.test/feed', self.cache)
        self.assertFalse(self.cache.exists())


if __name__ == '__main__':
    unittest.main()
