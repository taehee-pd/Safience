#!/bin/zsh
# Local recognition and nonpersistent synthetic WebKit pages. No Safience launch.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d /private/tmp/safience-extension-language.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
python3 - "$repo" "$scratch/PageSample.swift" <<'PYFIXTURE'
from pathlib import Path
import re, sys
repo, output = map(Path, sys.argv[1:])
source = (repo / 'Mac/Sources/Page.swift').read_text()
method = re.search(r"    func extensionLanguageText\(\).*?^    \}", source, re.S | re.M).group()
output.write_text('import Foundation\nimport WebKit\nextension Page {\n' + method + '\n}\n')
PYFIXTURE
# The fixture Page and extracted extension share one file so private remains local.
cat "$repo/Validation/mac-extension-language.swift" "$scratch/PageSample.swift" > "$scratch/fixture.swift"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -module-cache-path "$scratch/cache" \
  "$repo/Mac/Sources/ExtensionLanguage.swift" "$repo/PadCore/Sources/PadCore/HandsOff.swift" "$repo/PadCore/Sources/PadCore/Hosts.swift" "$scratch/fixture.swift" -o "$scratch/check"
"$scratch/check"
