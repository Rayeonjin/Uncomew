#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p .build/flow-tests
xcrun swiftc -module-cache-path .build/core-tests/ModuleCache \
 Sources/Uncomew/{DirectoryListing,CleanupAdvisor,StorageAnalyzer,StorageScan,StorageItem,ItemKnowledge,AppUninstaller,RemovalSafety,TrashService,DirectoryMeasurement,Shell}.swift \
 Tests/UncomewTests/FlowTests.swift -o .build/flow-tests/FlowTests
.build/flow-tests/FlowTests
