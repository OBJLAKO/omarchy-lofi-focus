"""Real mpv TLS playback through both controllers and an isolated local CA.

The wrapper supplies only fixture trust; verification must come from Skylofi.
No public stream, user trust store or audible output is used.
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ssl
import subprocess
import threading
import unittest

import player_test


class PlaybackTLSTest(unittest.TestCase):
    tearDown = player_test.PlayerTest.tearDown
    action = player_test.PlayerTest.action
    status = player_test.PlayerTest.status
    channel = player_test.PlayerTest.channel
    pid = player_test.PlayerTest.pid
    prop = player_test.PlayerTest.prop
    wait_for = player_test.PlayerTest.wait_for

    def setUp(self):
        player_test.PlayerTest.setUp(self)
        self.received_audio = threading.Event()
        ca = self.base/'fixture-ca.crt'
        ca_key = self.base/'fixture-ca.key'
        other_ca = self.base/'unrelated-ca.crt'
        certificate = self.base/'server.crt'
        key = self.base/'server.key'
        csr = self.base/'server.csr'
        extensions = self.base/'certificate.ext'
        # A trusted issuer cannot authorize a different hostname. Deliberately
        # omit an IP SAN so https://127.0.0.1 is an independent rejection case.
        extensions.write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost\n')
        commands = [
            ['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj', '/CN=Skylofi isolated TLS test CA', '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign', '-keyout', str(ca_key), '-out', str(ca)],
            ['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj', '/CN=Skylofi unrelated test CA', '-keyout', str(self.base/'unrelated-ca.key'), '-out', str(other_ca)],
            ['openssl', 'req', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost', '-keyout', str(key), '-out', str(csr)],
            ['openssl', 'x509', '-req', '-in', str(csr), '-CA', str(ca), '-CAkey', str(ca_key), '-set_serial', '1', '-days', '2', '-extfile', str(extensions), '-out', str(certificate)],
        ]
        for command in commands:
            subprocess.run(command, capture_output=True, check=True, timeout=10)
        self.ca = ca
        self.other_ca = other_ca
        self.env['LOFI_TEST_CA'] = str(ca)
        (self.bin/'mpv').write_text('#!/bin/sh\nexec /usr/bin/mpv --ao=null --tls-ca-file="$LOFI_TEST_CA" --loop-file=inf "$@"\n')
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                fixture.received_audio.set()
                data = (fixture.base/'tone.wav').read_bytes()
                self.send_response(200)
                self.send_header('Content-Type', 'audio/wav')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                    pass

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certificate, key)
        self.server.socket = context.wrap_socket(self.server.socket, server_side=True)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def start_source(self, host='localhost'):
        catalog_path = self.plugin/'stations.json'
        catalog = json.loads(catalog_path.read_text())
        for category in catalog['categories']:
            for station in category['stations']:
                if station['id'] == 'lofi-kalizo':
                    station['url'] = f'https://{host}:{self.server.server_port}/tone.wav'
        catalog_path.write_text(json.dumps(catalog))
        self.action('ui', 'fade', 'off')
        self.action('bg', 'off')
        self.action('start', 'lofi-kalizo')

    def audio_decoded(self):
        try:
            return self.prop('main', 'time-pos') is not None
        except player_test.PlaybackNotReady:
            return False

    def start_youtube_source(self):
        # Exercise the actual ytdl hook and the native extractor proxy, while
        # keeping the resolved CDN audio entirely inside the TLS fixture.
        payload = dict(id='BaW_jenozKc', title='Isolated TLS audio',
                       url=f'https://localhost:{self.server.server_port}/tone.wav',
                       ext='wav', protocol='https', duration=1, is_live=False)
        extractor = self.bin/'yt-dlp'
        extractor.write_text('#!/usr/bin/env python3\nprint(' + repr(json.dumps(payload)) + ')\n')
        extractor.chmod(0o755)
        self.action('ui', 'fade', 'off')
        self.action('bg', 'off')
        self.action('youtube-add', 'https://www.youtube.com/watch?v=BaW_jenozKc')
        self.action('start', 'youtube-BaW_jenozKc')

    def assert_certificate_rejected(self):
        def certificate_error():
            logs = self.base/'runtime/sky.lofi/logs'
            text = '\n'.join(path.read_text(errors='replace') for path in logs.glob('main.log*')).casefold()
            return 'certificate' in text and any(word in text for word in ('failed', 'not trusted', 'does not match'))
        self.wait_for(lambda: certificate_error() or self.received_audio.is_set())
        self.assertFalse(self.received_audio.is_set(), 'mpv downloaded audio before authenticating its HTTPS server')
        self.assertTrue(certificate_error(), 'mpv did not report the rejected certificate')
        self.assertFalse(self.audio_decoded(), 'unverified HTTPS audio was decoded')

    def test_trusted_https_source_decodes_audio(self):
        self.start_source()
        self.wait_for(self.audio_decoded)
        self.assertTrue(self.received_audio.is_set())
        self.assertTrue(self.prop('main', 'options/tls-verify'))

    def test_untrusted_https_issuer_cannot_supply_audio(self):
        self.env['LOFI_TEST_CA'] = str(self.other_ca)
        self.start_source()
        self.assert_certificate_rejected()

    def test_trusted_https_issuer_with_wrong_hostname_cannot_supply_audio(self):
        self.start_source('127.0.0.1')
        self.assert_certificate_rejected()

    def test_extractor_resolved_trusted_https_source_decodes_audio(self):
        self.start_youtube_source()
        self.wait_for(self.audio_decoded)
        self.assertTrue(self.received_audio.is_set())

    def test_extractor_resolved_untrusted_https_issuer_cannot_supply_audio(self):
        self.env['LOFI_TEST_CA'] = str(self.other_ca)
        self.start_youtube_source()
        self.assert_certificate_rejected()


if __name__ == '__main__':
    unittest.main()
