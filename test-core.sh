#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT_DIR/.build/core-tests"
xcrun swiftc -module-cache-path "$ROOT_DIR/.build/core-tests/ModuleCache" \
  "$ROOT_DIR/Sources/Uncomew/Shell.swift" \
  "$ROOT_DIR/Sources/Uncomew/DirectoryMeasurement.swift" \
  "$ROOT_DIR/Tests/UncomewTests/MeasurementTests.swift" \
  -o "$ROOT_DIR/.build/core-tests/MeasurementTests"
"$ROOT_DIR/.build/core-tests/MeasurementTests"
