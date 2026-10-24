#!/bin/zsh
# Standalone SwiftUI lifecycle fixture. No Safience data or CloudKit access.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d /private/tmp/safience-startup-windows.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
app="$scratch/StartupWindowsQA.app"
mkdir -p "$app/Contents/MacOS" "$scratch/data"
python3 - "$repo" "$scratch/fixture.swift" <<'PY'
from pathlib import Path
import re, sys
repo, output = map(Path, sys.argv[1:])
app = (repo / 'Mac/Sources/SafienceApp.swift').read_text().replace('import PadCore\n', '')
app = app.replace('struct SafienceApp: App {', 'struct SafienceApp: App {\n    init() { DispatchQueue.main.asyncAfter(deadline: .now() + 15) { print("FAIL Startup fixture timed out"); fflush(stdout); exit(124) } }')
seed_source = (repo / 'Mac/Sources/BrowserView.swift').read_text()
seed = re.search(r'struct WindowSeed: Codable, Hashable \{.*?\n\}', seed_source, re.S).group()
output.write_text(app + '\n' + seed + '\n' + (repo / 'Validation/mac-startup-windows.swift').read_text())
PY
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.safience.StartupWindowsQA.$RANDOM</string>
<key>CFBundleExecutable</key><string>StartupWindowsQA</string>
<key>CFBundleName</key><string>StartupWindowsQA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>SAFIENCE_DATA_ROOT</key><string>$scratch/data</string>
</dict></plist>
PLIST
xcrun swiftc -parse-as-library -module-cache-path "$scratch/cache" "$scratch/fixture.swift" -o "$app/Contents/MacOS/StartupWindowsQA"
codesign --force --sign - "$app" >/dev/null
SAFIENCE_DATA_ROOT="$scratch/data" "$app/Contents/MacOS/StartupWindowsQA" -ApplePersistenceIgnoreState YES
