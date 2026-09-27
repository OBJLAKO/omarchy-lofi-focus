"""Bounded, defensive loading of local preferences shared by controller/worker."""
import json
import math

MAX_JSON_BYTES = 1024 * 1024


def read_json(path, fallback):
    try:
        with path.open('r') as source:
            text = source.read(MAX_JSON_BYTES + 1)
        if len(text) > MAX_JSON_BYTES:
            return fallback
        value = json.loads(text)
        return value if isinstance(value, type(fallback)) else fallback
    except (OSError, ValueError, RecursionError):
        return fallback


def level(value, default=0):
    try:
        number = float(value)
        return max(0, min(100, number)) if math.isfinite(number) else default
    except (TypeError, ValueError, OverflowError):
        return default


def preferences(settings):
    """Keep valid selections; discard malformed fields before any audio work."""
    result = dict(settings)
    for key, default in dict(mainVolume=65, bgVolume=20, masterVolume=100,
                             natureVolume=25, noiseVolume=25, duckLevel=35,
                             fadeSeconds=3, revealSpeed=1).items():
        result[key] = level(result.get(key, default), default)
    for key in ('defaultStation', 'bgStation', 'noiseStation'):
        if key in result and not isinstance(result[key], str):
            result.pop(key)
    for key in ('mix', 'ducking', 'animations', 'revealAnimations', 'steamAnimation',
                'glowAnimation', 'equalizerAnimation', 'fadeEnabled', 'collapsibleSections'):
        if key in result and not isinstance(result[key], bool):
            result.pop(key)
    if 'natureLayers' in result:
        layers = result['natureLayers']
        result['natureLayers'] = {
            key: {'enabled': value.get('enabled') is True,
                  'volume': level(value.get('volume', 25), 25)}
            for key, value in (layers.items() if isinstance(layers, dict) else [])
            if isinstance(key, str) and key.startswith('noise-') and len(key) <= 80
            and all(c.isascii() and (c.isalnum() or c == '-') for c in key)
            and isinstance(value, dict)
        }
    return result


def session_state(value):
    """Ignore damaged transient state instead of losing Pause/Stop controls."""
    if not value:
        return {}
    result = dict(value)
    if result.get('mode') not in ('playing', 'paused', 'stopped'):
        return {}
    if not isinstance(result.get('station'), str):
        result['station'] = ''
    for key in ('started', 'retry_due', 'playing_since', 'progress_at', 'bookmark_at', 'pending_at'):
        number = result.get(key, 0)
        result[key] = number if isinstance(number, (int, float)) and math.isfinite(number) and number >= 0 else 0
    attempts = result.get('attempts', 0)
    result['attempts'] = int(level(attempts))
    pending = result.get('pending')
    if not (isinstance(pending, dict) and pending.get('action') in ('pause', 'stop')
            and isinstance(pending.get('at'), (int, float)) and math.isfinite(pending['at'])):
        result['pending'] = None
    if not isinstance(result.get('feed_token', ''), str):
        result['feed_token'] = ''
    return result
