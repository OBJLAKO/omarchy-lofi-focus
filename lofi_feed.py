"""Resolve bounded, HTTPS-only publisher RSS into a cached mpv playlist."""
import os
from pathlib import Path
import tempfile
import time
import urllib.parse
import urllib.request
# DTDs are rejected by NoDTD below.
import xml.etree.ElementTree as ET  # nosec B405

MAX_FEED_BYTES = 8 * 1024 * 1024


def https_url(value):
    try:
        parsed = urllib.parse.urlsplit(value)
        return (parsed.scheme == 'https' and bool(parsed.hostname)
                and parsed.username is None and parsed.password is None
                and not any(ord(c) < 33 or ord(c) == 127 for c in value))
    except ValueError:
        return False


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not https_url(newurl):
            raise ValueError('Podcast redirects must use HTTPS')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class NoDTD(ET.TreeBuilder):
    def doctype(self, name, pubid, system):
        raise ValueError('Podcast feeds must not contain a DTD')


def open_feed(url):
    if not https_url(url):
        raise ValueError('Podcast feed must use HTTPS')
    request = urllib.request.Request(url, headers={'User-Agent': 'LofiFocus/1.1'})
    return urllib.request.build_opener(HTTPSRedirect()).open(request, timeout=10)


def resolve(url, destination):
    path = Path(destination)
    temporary = None
    try:
        if path.exists() and time.time() - path.stat().st_mtime < 21600:
            return path
        with open_feed(url) as response:
            data = response.read(MAX_FEED_BYTES + 1)
        if len(data) > MAX_FEED_BYTES:
            raise ValueError('Podcast feed is too large')
        # The parser rejects DTD declarations before expanding document entities.
        root = ET.fromstring(data, parser=ET.XMLParser(target=NoDTD()))  # nosec B314
        urls = []
        for element in root.iter('enclosure'):
            value = element.get('url', '')
            if https_url(value):
                urls.append(value)
                if len(urls) == 12:
                    break
        if not urls:
            raise ValueError('No audio enclosures in podcast feed')
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent,
                                         prefix=path.name + '.', delete=False) as output:
            temporary = Path(output.name)
            output.write('#EXTM3U\n' + '\n'.join(urls) + '\n')
        os.replace(temporary, path)
    except Exception as error:
        if not path.exists():
            raise ValueError(f'Podcast unavailable: {error}') from error
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return path
