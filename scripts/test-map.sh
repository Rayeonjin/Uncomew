#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/map-tests"
xcrun swiftc -module-cache-path "$ROOT/.build/core-tests/ModuleCache" \
  "$ROOT/Sources/Uncomew/SpaceMapLayout.swift" \
  "$ROOT/Tests/UncomewTests/SpaceMapTests.swift" \
  -o "$ROOT/.build/map-tests/SpaceMapTests"
"$ROOT/.build/map-tests/SpaceMapTests"
