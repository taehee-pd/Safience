#!/bin/sh
# Actual native metadata admission with controlled delayed WebKit callbacks.
# No Safience app, CloudKit connection, user web view or data store starts.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d /private/tmp/safience-history-description.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
python3 - "$repo" "$scratch/fixture.swift" <<'PY'
from pathlib import Path
import sys
repo, output = map(Path, sys.argv[1:])
def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        if source[end] == '{': depth += 1
        if source[end] == '}': depth -= 1
        end += 1
    return source[start:end]
cloud = (repo / 'Shared/HistoryCloud.swift').read_text()
history = (repo / 'Shared/HistoryRecorder.swift').read_text()
parts = [(repo / 'Validation/history-description-origin.swift').read_text(),
         '\nextension HistoryCloud {\n' + block(cloud, '    struct LocalWriteContext:') + '\n}\n',
         '\n' + block(history, '@MainActor\nstruct PageHistory {')]
for platform, suffix in [('Mac', 'Mac'), ('App', 'App')]:
    source = (repo / platform / 'Sources/Page.swift').read_text()
    method = block(source, '    private func learnAbout() {').replace('private func learnAbout()', 'func learnAbout' + suffix + '()', 1)
    parts.append('\nextension FixturePage {\n' + method + '\n}\n')
output.write_text('\n'.join(parts))
PY
swiftc -parse-as-library -module-cache-path "$scratch/cache" "$scratch/fixture.swift" -o "$scratch/fixture"
"$scratch/fixture"
