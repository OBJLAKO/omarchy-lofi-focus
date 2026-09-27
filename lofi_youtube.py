"""Saved YouTube sources: canonical public video URLs, never arbitrary extractors."""
import re
from urllib.parse import parse_qs, urlsplit

MAX_SAVED = 40
VIDEO_ID = re.compile(r'[A-Za-z0-9_-]{11}\Z')
HOSTS = {'youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com'}


def canonical_url(value):
    if not isinstance(value, str) or len(value) > 2048:
        raise ValueError('Paste a YouTube video link (up to 2048 characters).')
    value = value.strip()
    if not value or any(ord(c) < 33 or ord(c) == 127 for c in value):
        raise ValueError('Paste a valid YouTube video link.')
    if value.startswith(('youtube.com/', 'www.youtube.com/', 'm.youtube.com/',
                         'music.youtube.com/', 'youtu.be/')):
        value = 'https://' + value
    try:
        parsed = urlsplit(value)
        if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.port not in (None, 443):
            raise ValueError
        parts = parsed.path.strip('/').split('/')
        if parsed.hostname == 'youtu.be' and len(parts) == 1:
            video = parts[0]
        elif parsed.hostname in HOSTS:
            if parsed.path == '/watch':
                ids = parse_qs(parsed.query).get('v', [])
                video = ids[0] if len(ids) == 1 else ''
            elif len(parts) == 2 and parts[0] in ('shorts', 'live', 'embed'):
                video = parts[1]
            else:
                video = ''
        else:
            video = ''
        if not VIDEO_ID.fullmatch(video):
            raise ValueError
    except ValueError:
        raise ValueError('Use a YouTube video, Shorts or live link; playlists and other sites are not supported.') from None
    return 'https://www.youtube.com/watch?v=' + video


def clean_title(value):
    return ' '.join(str(value).split())[:160]


def saved_entries(value):
    """Validate persisted data before it can reach mpv or become a file marker."""
    result = []
    if not isinstance(value, list):
        return result
    seen = set()
    for entry in value:
        if not isinstance(entry, dict):
            continue
        try:
            url = canonical_url(entry.get('url'))
        except ValueError:
            continue
        video = url.rsplit('=', 1)[1]
        identity = 'youtube-' + video
        if identity in seen:
            continue
        seen.add(identity)
        position = entry.get('position', 0)
        if not isinstance(position, (int, float)) or not 0 <= position < 604800:
            position = 0
        result.append(dict(id=identity, url=url,
                           name=clean_title(entry.get('name') or 'YouTube · ' + video),
                           position=round(position, 1)))
        if len(result) == MAX_SAVED:
            break
    return result
