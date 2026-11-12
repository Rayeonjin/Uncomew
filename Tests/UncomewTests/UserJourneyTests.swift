import Foundation

@main
struct UserJourneyTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        func wait(_ condition: () -> Bool) async throws {
            for _ in 0..<500 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            preconditionFailure("Journey did not finish")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let downloads = home + "/Downloads"
        let installer = downloads + "/JourneyFixture.dmg"
        let archive = downloads + "/JourneyFixture.zip"
        let operation: StorageAnalyzer.ScanOperation = { roots, publish in
            let path = roots[0]
            if path == "/fixture/failure" { throw NSError(domain: "Journey", code: 1) }
            var root = StorageNode(path: path, parent: nil, type: .folder, insidePackage: false)
            if path == "/fixture/unreadable" {
                root.measurement = .unavailable; root.permissionDenied = true
                await publish(ScanBatch(nodes: [root], currentPath: path, visited: 1))
                return
            }
            await publish(ScanBatch(nodes: [root], currentPath: path, visited: 1))
            try await Task.sleep(nanoseconds: 30_000_000)
            try Task.checkCancellation()
            var first = StorageNode(path: installer, parent: path, type: .file, insidePackage: false)
            first.allocatedBytes = 500_000_000; first.measurement = .complete
            var second = StorageNode(path: archive, parent: path, type: .file, insidePackage: false)
            second.allocatedBytes = 200_000_000; second.measurement = .complete
            root.children = [first.path, second.path]; root.allocatedBytes = 700_000_000; root.measurement = .complete
            await publish(ScanBatch(nodes: [root, first, second], currentPath: path, visited: 3))
        }
        // Synthetic metadata only: no user files are read, created, moved or deleted by these scans.
        for round in 1...3 {
            let analyzer = StorageAnalyzer(runScan: operation)
            analyzer.analyze(roots: [downloads])
            try await wait { !analyzer.isScanning && !analyzer.preparingCandidates }
            check(analyzer.candidates.count == 2 && analyzer.selectedCandidatePath == installer,
                  "First-time reviewer gets an initial candidate")
            analyzer.candidateCategory = CleanupCandidate.Category.archives.rawValue
            analyzer.reconcileCandidateSelection()
            check(analyzer.selectedCandidatePath == archive, "Category selects a matching item")
            let snapshot = analyzer.nodes
            let before = analyzer.state
            analyzer.browseSearch = "does-not-match"
            analyzer.showInTree(analyzer.nodes[archive]!)
            analyzer.reconcileCandidateSelection()
            check(analyzer.selectedCandidatePath == archive && analyzer.candidateCategory == CleanupCandidate.Category.archives.rawValue,
                  "Returning from storage preserves candidate context")
            check(analyzer.nodes == snapshot && analyzer.state == before && analyzer.browseSearch.isEmpty,
                  "Jump reveals the target without restarting the scan")
            analyzer.keptCandidatePaths.insert(archive); analyzer.reconcileCandidateSelection()
            check(analyzer.visibleCandidates.isEmpty && analyzer.selectedCandidatePath == nil,
                  "Keeping the only filtered item produces a truthful empty result")
            analyzer.showKeptCandidates = true; analyzer.reconcileCandidateSelection()
            check(analyzer.selectedCandidatePath == archive && analyzer.nodes == snapshot,
                  "Reviewing kept items restores context without changing files")

            // Storage-focused personas: a novice with empty results, a power user
            // combining filters, and a user switching tasks without rescanning.
            func visible() -> [StorageNode] {
                StorageRanking.top(analyzer.nodes.values, limit: analyzer.browseDisplayLimit, byName: analyzer.browseSortByName) {
                    analyzer.browseFilter.matches($0) &&
                    (analyzer.browseIncludePackages || !$0.insidePackage) &&
                    (analyzer.browseSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(analyzer.browseSearch)) &&
                    (analyzer.mode == .tree || (analyzer.mode == .folders ? $0.isFolder : $0.type == .file))
                }
            }
            analyzer.browseSortByName = true
            analyzer.browseFiles(in: analyzer.nodes[downloads]!)
            check(visible().map(\.path) == [installer, archive], "Folder drilldown uses descending size without rescanning")
            analyzer.browseFileKind = .archive
            analyzer.browseMinimumSize = .mb100
            analyzer.browseSearch = "ZIP"
            check(visible().map(\.path) == [archive], "Combined kind, size, scope and case-insensitive search locate one file")
            analyzer.browseMinimumSize = .gb1
            check(visible().isEmpty, "Over-restrictive conditions show no false match")
            analyzer.showCurrentRanking(.files)
            check(visible().count == 2 && analyzer.nodes == snapshot, "Empty-result recovery reuses all current results")
            analyzer.browseFileKind = .video
            analyzer.mode = .folders
            check(visible().map(\.path) == [downloads], "Folder switch removes incompatible hidden kind condition")
            analyzer.browseSearch = "missing"
            analyzer.browseMinimumSize = .gb10
            analyzer.showInTree(analyzer.nodes[archive]!)
            check(!analyzer.hasBrowseFilters && analyzer.selectedPath == archive, "Explicit tree jump escapes restrictive filters")
            check(analyzer.keptCandidatePaths.contains(archive), "Storage exploration does not erase the user's keep decision")

            analyzer.analyze(roots: [downloads])
            try await wait { !analyzer.nodes.isEmpty }
            analyzer.cancel()
            try await wait { !analyzer.isScanning && !analyzer.preparingCandidates }
            check(analyzer.state == .cancelled && analyzer.nodes[downloads]?.measurement == .partial,
                  "Impatient user retains partial results after cancellation")
            analyzer.reanalyze()
            try await wait { !analyzer.isScanning && !analyzer.preparingCandidates }
            check(analyzer.roots == [downloads] && analyzer.nodes[archive] != nil,
                  "Retry preserves the user's chosen scope")

            analyzer.analyze(roots: ["/fixture/unreadable"])
            try await wait { !analyzer.isScanning && !analyzer.preparingCandidates }
            check(analyzer.issueCount == 1 && analyzer.nodes["/fixture/unreadable"]?.allocatedBytes == nil && analyzer.candidates.isEmpty,
                  "Unreadable location is unknown rather than empty or clean")
            analyzer.analyze(roots: ["/fixture/failure"])
            try await wait { !analyzer.isScanning }
            if case .failed = analyzer.state { checks += 1 } else { preconditionFailure("Failure is not visible") }
            analyzer.analyze(roots: [downloads])
            try await wait { !analyzer.isScanning && !analyzer.preparingCandidates }
            check(analyzer.issueCount == 0 && analyzer.candidateCategory == "전체" && analyzer.candidates.count == 2,
                  "Recovery clears old errors and filters")
            print("Journey round \(round): candidate review, navigation, keep/revisit, cancellation, denied access, failure recovery passed.")
        }

        var root = StorageNode(path: "/fixture", parent: nil, type: .folder, insidePackage: false)
        var nodes: [String: StorageNode] = [:]
        for index in 0..<2_000 {
            var node = StorageNode(path: "/fixture/\(index).bin", parent: root.path, type: .file, insidePackage: false)
            node.allocatedBytes = Int64(index); node.measurement = .complete
            nodes[node.path] = node; root.children.append(node.path)
        }
        nodes[root.path] = root
        let target = "/fixture/0.bin"
        let rows = StorageRanking.tree(nodes: nodes, roots: [root.path], expanded: [root.path],
                                       selected: target, limit: 300, byName: false, includePackages: false)
        check(rows.count == 300 && rows.contains(where: { $0.node.path == target }),
              "Low-ranked jump target remains visible without rendering all 2,000 rows")
        check(rows.first?.node.path == root.path && rows.last?.node.path == target,
              "Tree retains hierarchy and relative sort order")
        var package = StorageNode(path: "/fixture/Test.app", parent: root.path, type: .package, insidePackage: false)
        let interior = StorageNode(path: package.path + "/Contents", parent: package.path, type: .folder, insidePackage: true)
        package.children = [interior.path]; nodes[package.path] = package; nodes[interior.path] = interior
        root.children.append(package.path); nodes[root.path] = root
        let expanded: Set<String> = [root.path, package.path]
        let packageRows = StorageRanking.tree(nodes: nodes, roots: [root.path], expanded: expanded,
                                              selected: interior.path, limit: 300, byName: false, includePackages: true)
        check(packageRows.contains(where: { $0.node.path == package.path && $0.depth == 1 }) &&
              packageRows.contains(where: { $0.node.path == interior.path && $0.depth == 2 }),
              "Package jump includes ancestors within the page limit")
        let hiddenRows = StorageRanking.tree(nodes: nodes, roots: [root.path], expanded: expanded,
                                             selected: interior.path, limit: 300, byName: false, includePackages: false)
        check(!hiddenRows.contains(where: { $0.node.path == interior.path }), "Package visibility option is respected")
        print("Passed \(checks) journey checks across three rounds. Synthetic metadata only; no Trash operation.")
    }
}
