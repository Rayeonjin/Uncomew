#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/.build/workflow-tests"
xcrun swiftc -module-cache-path "$ROOT/.build/core-tests/ModuleCache" \
  "$ROOT/Sources/Uncomew/DirectoryListing.swift" "$ROOT/Sources/Uncomew/StorageItem.swift" "$ROOT/Sources/Uncomew/StorageScan.swift" "$ROOT/Sources/Uncomew/StorageRanking.swift" "$ROOT/Sources/Uncomew/ItemKnowledge.swift" \
  "$ROOT/Sources/Uncomew/RemovalSafety.swift" "$ROOT/Tests/UncomewTests/StorageWorkflowTests.swift" \
  -o "$ROOT/.build/workflow-tests/StorageWorkflowTests"
"$ROOT/.build/workflow-tests/StorageWorkflowTests"
