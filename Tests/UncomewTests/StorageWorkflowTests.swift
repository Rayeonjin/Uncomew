import Foundation
import Darwin

actor Results {
    var nodes: [String: StorageNode] = [:]
    var batches = 0
    func accept(_ batch: ScanBatch) { batches += 1; for node in batch.nodes { nodes[node.path] = node } }
}

@main
struct StorageWorkflowTests {
    static func main() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["UNCOMEW_TEST_ROOT"] ?? fm.currentDirectoryPath).appendingPathComponent(".build/workflow-tests").appendingPathComponent("Uncomew-workflow-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        var capacity = DiskSummary()
        capacity.totalBytes = 100; capacity.availableBytes = 20
        check(capacity.finderComparableBytes == nil, "Missing estimate is unknown, not zero")
        capacity.importantAvailableBytes = 0
        check(capacity.finderComparableBytes == nil, "Denied API zero must not imply full disk")
        capacity.importantAvailableBytes = 25
        check(capacity.additionalAvailableBytes == 5, "Only additional estimate is compared, never summed twice")
        capacity.importantAvailableBytes = 101
        check(capacity.finderComparableBytes == nil, "Inconsistent estimate is unavailable")
        capacity.availableBytes = 0; capacity.importantAvailableBytes = 0
        check(capacity.finderComparableBytes == 0, "Real full disk retains zero")
        let nested = root.appendingPathComponent("한글 space/sub")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        let regular = nested.appendingPathComponent("large file.bin")
        try Data(repeating: 42, count: 1024 * 1024).write(to: regular)
        let hidden = root.appendingPathComponent(".hidden")
        try Data([1,2,3]).write(to: hidden)
        let link = root.appendingPathComponent("cycle")
        try fm.createSymbolicLink(at: link, withDestinationURL: root)
        let hardlink = root.appendingPathComponent("hardlink")
        try fm.linkItem(at: regular, to: hardlink)
        let app = root.appendingPathComponent("Fixture.app")
        try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier":"com.example.fixture", "CFBundleName":"Fixture", "CFBundleExecutable":"Fixture", "CFBundlePackageType":"APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data(repeating: 2, count: 4096).write(to: app.appendingPathComponent("Contents/MacOS/Fixture"))
        let sparse = root.appendingPathComponent("sparse")
        _ = fm.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 64 * 1024 * 1024); try handle.close()
        let results = Results()
        try await StorageScan.run(roots: [root.path, nested.path]) { await results.accept($0) }
        // The scanner standardizes keys; /private/var and /var can name the same fixture.
        let nodes = await results.nodes
        check(nodes[root.standardizedFileURL.path]?.measurement == .complete, "Whole fixture scan completes")
        check(nodes[regular.standardizedFileURL.path]?.parent == nested.standardizedFileURL.path, "Tree parent relation")
        check(nodes[hidden.standardizedFileURL.path]?.type == .file, "Hidden files included")
        check(nodes[link.standardizedFileURL.path]?.type == .symbolicLink && nodes[link.standardizedFileURL.path]?.children.isEmpty == true, "Symlink cycle never traversed")
        check(nodes[app.standardizedFileURL.path]?.type == .package && nodes[app.standardizedFileURL.path]?.bundleID == "com.example.fixture", "App metadata")
        check(nodes[app.appendingPathComponent("Contents/Info.plist").standardizedFileURL.path]?.insidePackage == true, "Package contents marked")
        check((nodes[sparse.standardizedFileURL.path]?.logicalBytes ?? 0) > (nodes[sparse.standardizedFileURL.path]?.allocatedBytes ?? Int64.max), "Sparse logical/allocated sizes distinguished")
        check(nodes.values.filter { $0.note?.contains("하드 링크") == true }.count == 1, "Hard link is not counted twice")
        let plistSize = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")).count
        check(nodes[root.standardizedFileURL.path]?.logicalBytes == 64 * 1024 * 1024 + 1024 * 1024 + 3 + Int64(plistSize) + 4096 + nodes[link.standardizedFileURL.path]!.logicalBytes!, "Non-overlapping logical aggregate")
        check(StorageScan.normalizedRoots([root.path, nested.path, root.path]) == [root.standardizedFileURL.path], "Overlapping roots removed")
        check(StorageScan.normalizedRoots(["/a", "/ab"]) == ["/a", "/ab"], "Root path boundaries")
        let rankingFixture: [StorageNode] = (0..<12_000).map { index in
            var node = StorageNode(path: "/tmp/rank-\(index)", parent: nil, type: .file, insidePackage: false)
            node.allocatedBytes = index.isMultiple(of: 101) ? nil : Int64(index % 97)
            return node
        }
        let sizeOrder = rankingFixture.sorted {
            if $0.allocatedBytes != $1.allocatedBytes { return ($0.allocatedBytes ?? -1) > ($1.allocatedBytes ?? -1) }
            return $0.path < $1.path
        }.prefix(300).map(\.path)
        check(StorageRanking.top(rankingFixture, limit: 300, including: { _ in true }).map(\.path) == sizeOrder,
              "Bounded size ranking matches full ordering, including unknown sizes and ties")
        let nameOrder = rankingFixture.filter { $0.allocatedBytes != nil }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }.prefix(50).map(\.path)
        check(StorageRanking.top(rankingFixture, limit: 50, byName: true, including: { $0.allocatedBytes != nil }).map(\.path) == nameOrder,
              "Bounded name ranking honors filters and matches full ordering")
        check(StorageRanking.top(rankingFixture, limit: 0, including: { _ in true }).isEmpty, "Empty page requests do not rank")
        let missing = Results()
        try await StorageScan.run(roots: [root.appendingPathComponent("missing").path]) { await missing.accept($0) }
        let missingNodes = await missing.nodes
        check(missingNodes.values.first?.allocatedBytes == nil, "Missing path is unknown, not zero")
        let limited = Results()
        try await StorageScan.run(roots: [root.path], limit: 3) { await limited.accept($0) }
        let limitNodes = await limited.nodes
        check(limitNodes.count <= 3 && limitNodes[root.standardizedFileURL.path]?.measurement == .partial, "Limit yields truthful partial results")
        let protected = root.appendingPathComponent("protected")
        try fm.createDirectory(at: protected, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: protected.path)
        let denied = Results()
        try await StorageScan.run(roots: [root.path]) { await denied.accept($0) }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: protected.path)
        let deniedNodes = await denied.nodes
        check(deniedNodes[protected.standardizedFileURL.path]?.measurement == .unavailable && deniedNodes[root.standardizedFileURL.path]?.measurement == .partial, "Denied descendants propagate partial state")
        let cancelResults = Results()
        let task = Task {
            try await StorageScan.run(roots: [root.path]) { batch in
                await cancelResults.accept(batch)
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do { try await task.value; preconditionFailure("Cancellation ignored") } catch is CancellationError { checks += 1 }
        let cancelled = await cancelResults.nodes
        check(!cancelled.isEmpty, "Cancellation preserves first results")

        let known = StorageNode(path: "/Users/test/Library/Application Support/MobileSync/Backup/device-secret", parent: nil, type: .folder, insidePackage: false)
        let knowledge = ItemKnowledge.explanation(for: known, home: "/Users/test")
        check(knowledge.title.contains("백업") && knowledge.source != nil, "Known path explanation with official source")
        check(knowledge.searchQuery?.contains("device-secret") == false && knowledge.searchQuery?.contains("/Users") == false, "Known-folder query never leaks private path")
        let unknown = StorageNode(path: "/Users/test/Confidential Client", parent: nil, type: .folder, insidePackage: false)
        check(ItemKnowledge.explanation(for: unknown, home: "/Users/test").searchQuery == nil, "Unknown private folder not web searched")
        check(ItemKnowledge.explanation(for: nodes[app.standardizedFileURL.path]!).searchQuery == "com.example.fixture mac app official", "App query uses validated identifier only")
        check(!ItemKnowledge.validBundleID("../../secret") && !ItemKnowledge.validBundleID("com.example/name"), "Reject traversal identifiers")
        let candidates = RemovalSafety.relatedPaths(bundleID: "com.example.app", home: root.path)
        check(!candidates.contains { $0.path.contains("Group Containers") || $0.path.contains("com.example.application") }, "No shared/fuzzy paths")
        check(RemovalSafety.relatedPaths(bundleID: "../escape", home: root.path).isEmpty, "Reject malicious metadata")
        check(RemovalSafety.approvedInstalledApp("/Applications/Example.app", home: "/Users/fixture"), "Standard installed app is eligible")
        check(RemovalSafety.approvedInstalledApp("/Applications/Tools/Example.app", home: "/Users/fixture"), "Shallow application subfolder is eligible")
        check(RemovalSafety.approvedInstalledApp("/Users/fixture/Applications/Example.app", home: "/Users/fixture"), "User Applications is eligible")
        check(!RemovalSafety.approvedInstalledApp(root.appendingPathComponent("Fixture.app").path, home: "/Users/fixture"), "Development bundle is inspection-only")
        check(!RemovalSafety.approvedInstalledApp("/System/Applications/Example.app", home: "/Users/fixture"), "System app is excluded")
        check(!RemovalSafety.approvedInstalledApp("/Applications/../System/Example.app", home: "/Users/fixture"), "Traversal cannot escape approved root")
        check(!RemovalSafety.approvedInstalledApp("/ApplicationsX/Example.app", home: "/Users/fixture"), "Prefix collision is excluded")
        check(!RemovalSafety.approvedInstalledApp("/Users/fixture/Applications/a/b/c/Example.app", home: "/Users/fixture"), "Deep nested bundle is excluded")
        let captured = RemovalSafety.capture(path: regular.path, allowedParent: nested.path, bytes: 1)!
        check(RemovalSafety.isStillValid(captured), "Unchanged candidate revalidates")
        try fm.moveItem(at: regular, to: nested.appendingPathComponent("original"))
        try Data([1]).write(to: regular)
        check(!RemovalSafety.isStillValid(captured), "Replacement inode rejected")
        check(RemovalSafety.capture(path: link.path, allowedParent: root.path, bytes: 0) == nil, "Symlink removal rejected")
        check(RemovalSafety.capture(path: regular.path, allowedParent: root.path, bytes: 0) == nil, "Outside expected parent rejected")
        print("Passed \(checks) storage/knowledge/removal-safety checks. No Trash operation performed.")
    }
}
