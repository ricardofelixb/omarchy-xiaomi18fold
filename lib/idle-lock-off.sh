#!/usr/bin/env bash
# Turn Omarchy's idle lock off (.idle.lock = 0 in shell.json; its idle service treats a
# timeout <= 0 as disabled). The container user's password is locked, so the lock screen can
# never be unlocked; Android's own lock protects the phone. Every other key stays, including
# .idle.screensaver. Omarchy reads $HOME/.config whatever XDG_CONFIG_HOME says, and only
# accepts a file whose "version" is 1 (its own editors add it when missing, so this does too).
# Numbers are written back exactly as they were read (1e400 and 1e2 stay as they are).
# A symlinked file is written through. A missing, read-only or non-strict-JSON file, anything
# but one object or a version other than 1 is left alone with a warning and exit 1.
# Running it again changes nothing.
set -euo pipefail

file=$HOME/.config/omarchy/shell.json
if [[ -L $file ]]; then file=$(readlink -f -- "$file") || file=''; fi
exec python3 -I - "$file" <<'PY'
import json, os, re, secrets, sys, tempfile

path = sys.argv[1]


def refuse(reason):
    print(f'WARNING: {path}: {reason}; idle lock left on.', file=sys.stderr)
    sys.exit(1)


# Numbers are kept as their source text behind a per-run marker, so rewriting the file cannot
# change them; the marker and its quotes are stripped from the output.
marker = secrets.token_hex(16)


class Number(str):
    def __new__(cls, text):
        return super().__new__(cls, marker + text)

    def value(self):
        return float(self[len(marker):])


def not_strict(constant):
    raise ValueError(f'{constant} is not JSON')


if not os.path.isfile(path) or not os.access(path, os.W_OK):
    refuse('missing or read-only')
try:
    with open(path, encoding='utf-8') as f:
        cfg = json.load(f, parse_constant=not_strict, parse_int=Number, parse_float=Number)
except (OSError, ValueError) as error:
    refuse(f'not valid JSON ({error})')
if not isinstance(cfg, dict):
    refuse('not a JSON object')
if 'version' in cfg and not (isinstance(cfg['version'], Number) and cfg['version'].value() == 1):
    refuse('Omarchy only reads "version": 1')
cfg = {'version': 1, **cfg}
idle = cfg.get('idle')
cfg['idle'] = {**(idle if isinstance(idle, dict) else {}), 'lock': 0}
text = json.dumps(cfg, indent=2, ensure_ascii=False) + '\n'
text = re.sub('"' + marker + '([^"]*)"', r'\1', text)
fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path) + '.', dir=os.path.dirname(path))
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as out:
        out.write(text)
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)
except BaseException:
    os.unlink(tmp)
    raise
PY
