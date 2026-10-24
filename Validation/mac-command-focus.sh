#!/bin/sh
# Native field behavior only. No Safience launch, visible window or browser data.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d /private/tmp/safience-command-focus.XXXXXX)
trap 'rm -f "$scratch/fixture.swift" "$scratch/fixture"; rmdir "$scratch"' EXIT
cat "$repo/Validation/mac-command-focus.swift" > "$scratch/fixture.swift"
sed -n '/^enum FieldKey {/,${p;}' "$repo/Mac/Sources/CommandBar.swift" >> "$scratch/fixture.swift"
swiftc -parse-as-library "$scratch/fixture.swift" -o "$scratch/fixture"
"$scratch/fixture"
