#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p .build/improvement-tests
xcrun swiftc -O -module-cache-path .build/core-tests/ModuleCache \
 Sources/Uncomew/{DirectoryListing,StorageScan,CleanupAdvisor,ItemKnowledge,RemovalSafety,TrashService}.swift \
 Tests/UncomewTests/ImprovementTests.swift -o .build/improvement-tests/ImprovementTests
.build/improvement-tests/ImprovementTests "$@"
