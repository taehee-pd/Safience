#!/bin/sh
# Exercises native SwiftUI menu routing with actual Close commands and closeTab.
# The synthetic model never starts Safience, WebKit, CloudKit or a data store.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d /private/tmp/safience-close-commands.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/CloseCommandsQA.app/Contents/MacOS"
cat "$repo/Validation/mac-close-commands.swift" "$repo/Mac/Sources/BrowserCloseCommands.swift" > "$scratch/fixture.swift"
python3 - "$repo/Mac/Sources/WindowModel.swift" "$scratch/fixture.swift" <<'PY'
import sys
source = open(sys.argv[1]).read()
start = source.index('    func closeTab(_ id: UUID? = nil) {')
brace = source.index('{', start)
depth = 1
end = brace + 1
while depth:
    if source[end] == '{': depth += 1
    if source[end] == '}': depth -= 1
    end += 1
with open(sys.argv[2], 'a') as file:
    file.write('\nextension WindowModel {\n' + source[start:end] + '\n}\n')
PY
cat > "$scratch/CloseCommandsQA.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>net.taehee.safience.CloseCommandsQA</string>
<key>CFBundleName</key><string>Close Commands QA</string>
<key>CFBundleExecutable</key><string>CloseCommandsQA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -parse-as-library -module-cache-path "$scratch/cache" "$scratch/fixture.swift" -o "$scratch/CloseCommandsQA.app/Contents/MacOS/CloseCommandsQA"
"$scratch/CloseCommandsQA.app/Contents/MacOS/CloseCommandsQA"
