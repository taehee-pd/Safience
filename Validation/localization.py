#!/usr/bin/env python3
"""Check translated keys and printf placeholders without changing catalogs."""
from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / 'Shared/Resources/Localizable.xcstrings').read_text())
strings = catalog['strings']
errors = []
placeholder = re.compile(r'(?<!%)%(?:\d+\$)?(?:ll|l)?[@diuf]')

def formats(value):
    return sorted(re.sub(r'%\d+\$', '%', p) for p in placeholder.findall(value))

def read_strings(path):
    result = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r'("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");', line)
        if not match:
            errors.append(f'{path}: invalid strings entry')
            continue
        key, value = map(json.loads, match.groups())
        if key in result:
            errors.append(f'{path}: duplicate {key!r}')
        result[key] = value
    return result

core = {language: read_strings(root / f'PadCore/Sources/PadCore/Resources/{language}.lproj/Localizable.strings')
        for language in ['en', 'ko']}
if core['en'].keys() != core['ko'].keys():
    errors.append('Core language keys differ')
for key, entry in strings.items():
    try:
        en = entry['localizations']['en']['stringUnit']['value']
        ko = entry['localizations']['ko']['stringUnit']['value']
        if en != key or not ko:
            errors.append(f'Incomplete catalog entry: {key!r}')
        if formats(en) != formats(ko):
            errors.append(f'Placeholder mismatch: {key!r}')
    except KeyError:
        errors.append(f'Missing language: {key!r}')
for key, value in core['en'].items():
    if formats(value) != formats(core['ko'].get(key, '')):
        errors.append(f'Core placeholder mismatch: {key!r}')

# Runtime lookup keys are explicit; web content and user names are not localized keys.
for directory in ['App/Sources', 'Mac/Sources', 'Shared', 'PadCore/Sources/PadCore']:
    for source in (root / directory).rglob('*.swift'):
        for match in re.finditer(r'BrowserText\.localized\(("(?:[^"\\]|\\.)*")\)', source.read_text()):
            key = json.loads(match.group(1))
            if key not in core['en']:
                errors.append(f'{source.relative_to(root)}: missing key {key!r}')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'{len(strings)} bilingual catalog entries and {len(core["en"])} core keys verified.')
