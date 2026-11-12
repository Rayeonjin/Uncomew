#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p .build/journey-tests
xcrun swiftc -module-cache-path .build/core-tests/ModuleCache \
 Sources/Uncomew/{DirectoryListing,CleanupAdvisor,StorageAnalyzer,StorageScan,StorageRanking,StorageItem,ItemKnowledge}.swift \
 Tests/UncomewTests/UserJourneyTests.swift -o .build/journey-tests/UserJourneyTests
.build/journey-tests/UserJourneyTests
