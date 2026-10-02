#!/usr/bin/env python3
"""Benchmark-only resident adapter. Uses the unchanged Python controller.

Not a production daemon: stdin/stdout transport and single benchmark client.
It isolates process/import overhead from the benefits of another language.
"""
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lofi_backend import Player

player = Player()
print('ready', flush=True)
for line in sys.stdin:
    try:
        args = json.loads(line)
        player.acquire()
        try:
            result = player.action(args[0], args[1:])
        finally:
            player.release()
        print(json.dumps({'ok': True, 'state': result}), flush=True)
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error)}), flush=True)
