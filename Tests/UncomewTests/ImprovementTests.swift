import Foundation
import Darwin

actor ScanRecord {
    var nodes: [String: StorageNode] = [:]
    var first: Date?
    func accept(_ batch: ScanBatch) {
        if first == nil { first = Date() }
        for node in batch.nodes { nodes[node.path] = node }
    }
}
@main struct ImprovementTests {
    static func main() async throws {
        let fm = FileManager.default
        let home = "/Users/fixture"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        func node(_ relative: String, bytes: Int64 = 200_000_000, type: StorageNode.EntryType = .file, days: Int = 0) -> StorageNode {
            var node = StorageNode(path: home + "/" + relative, parent: nil, type: type, insidePackage: false)
            node.allocatedBytes = bytes; node.measurement = .complete
            node.modifiedAt = now.addingTimeInterval(-Double(days) * 86400)
            return node
        }
        func classify(_ node: StorageNode) -> CleanupCandidate? { CleanupAdvisor.candidate(for: node, home: home, now: now) }
        let suite = "Uncomew.decisions." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CandidateDecisionStore(defaults: defaults)
        var original = node("Downloads/remember.dmg")
        original.fileIdentity = "device:inode:birth:change"
        store.save(.keep, for: original)
        check(CandidateDecisionStore(defaults: defaults).decision(for: original) == .keep, "Keep survives store restart")
        var changed = original
        changed.fileIdentity = "different inode"
        check(store.decision(for: changed) == nil, "Replacement at same path does not inherit decision")
        changed = original; changed.allocatedBytes = 300_000_000
        check(store.decision(for: changed) == nil, "Changed size requires review")
        changed = original; changed.modifiedAt = now
        check(store.decision(for: changed) == .keep, "Unchanged timestamp preserves note")
        changed.modifiedAt = now.addingTimeInterval(1)
        check(store.decision(for: changed) == nil, "Modified file requires review")
        changed = original; changed.measurement = .partial
        check(store.decision(for: changed) == nil, "Partial scan cannot reuse complete decision")
        for decision in [CandidateDecision.later, .review] {
            store.save(decision, for: original)
            check(CandidateDecisionStore(defaults: defaults).decision(for: original) == decision, "Review state survives restart")
        }
        store.save(nil, for: original)
        check(CandidateDecisionStore(defaults: defaults).decision(for: original) == nil, "Cleared note stays cleared")
        defaults.set(Data("invalid".utf8), forKey: "Uncomew.candidateDecisions.v1")
        check(CandidateDecisionStore(defaults: defaults).decision(for: original) == nil, "Corrupt notes never become decisions")
        let smallInstaller = node("Downloads/small.dmg", bytes: 30_000_000)
        let largePersonal = node("Downloads/family.zip", bytes: 8_000_000_000)
        var incomplete = node("Downloads/incomplete.dmg", bytes: 9_000_000_000)
        incomplete.measurement = .partial
        let ordered = CleanupAdvisor.candidates(in: [largePersonal, incomplete, smallInstaller], home: home, now: now)
        check(ordered.map(\.id) == [smallInstaller.path, largePersonal.path, incomplete.path], "Reviewability before size; incomplete last")
        check(ordered.allSatisfy { !$0.questions.isEmpty && !$0.priorityReason.isEmpty }, "Every candidate explains priority and asks questions")
        check(classify(node("Downloads/setup.DMG"))?.category == .installers, "Installer extension is case insensitive")
        check(classify(node("Downloads/document.pdf", days: 91))?.category == .downloads, "Old downloaded document is review only")
        check(classify(node("Downloads/document.pdf", days: 89)) == nil, "Recent document not recommended")
        check(classify(node("Documents/document.pdf", days: 365)) == nil, "Personal documents outside Downloads not classified by age")
        check(classify(node("Downloads/archive.zip"))?.category == .archives, "Large downloaded archive")
        check(classify(node("Downloads/tiny.zip", bytes: 100)) == nil, "Small item excluded")
        check(classify(node("Downloads/cloud.dmg", bytes: 0)) == nil, "Online-only placeholder has no local candidate size")
        check(classify(node("Library/CloudStorage/service/app.app", type: .package)) == nil, "Cloud data excluded")
        check(classify(node("Library/Mobile Documents/app.app", type: .package)) == nil, "iCloud Drive excluded")
        check(classify(node("Library/Application Support/app", type: .folder)) == nil, "Support data not called cache")
        let cache = node("Library/Caches/test", type: .folder)
        let nested = node("Library/Caches/test/nested.app", type: .package)
        check(classify(cache)?.category == .caches, "Direct cache child classified")
        check(CleanupAdvisor.candidates(in: [cache, nested], home: home, now: now).map(\.id) == [cache.path], "No overlapping parent and child candidates")
        check(classify(node("Library/Developer/Xcode/DerivedData", type: .folder))?.category == .builds, "Build-data exact root")
        check(classify(node("Library/Developer/Xcode/Archives", type: .folder)) == nil, "Archives never confused with regenerable builds")
        check(classify(node("Applications/Large.app", type: .package))?.category == .applications, "Large app candidate")
        var special = node("Downloads/old.pdf", days: 99)
        special.modifiedAt = nil
        check(classify(special) == nil, "Unknown date not old")
        special = node("Downloads/setup.dmg"); special.measurement = .unavailable
        check(classify(special) == nil, "Unavailable sizes excluded")
        special.measurement = .partial
        check(classify(special)?.node.sizeText.contains("일부") == true, "Partial candidate stays partial")
        special.linkCount = 2
        check(classify(special) == nil, "Hard-link candidate does not imply reclaimable bytes")
        let delayed = DispatchSemaphore(value: 0)
        do {
            _ = try DirectoryListing.read("fixture", timeout: 0.05) { delayed.wait(); return ["late"] }
            fatalError("Timed-out filesystem read accepted")
        } catch { checks += 1 }
        delayed.signal()
        let cancelledRead = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DirectoryListing.read("fixture", loader: { fatalError("Cancelled work started") })
        }
        do { _ = try await cancelledRead.value; fatalError("Cancelled listing accepted") }
        catch is CancellationError { checks += 1 }
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["UNCOMEW_TEST_ROOT"] ?? fm.currentDirectoryPath).appendingPathComponent(".build/improvement-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let big = root.appendingPathComponent("big"), small = root.appendingPathComponent("small")
        try fm.createDirectory(at: big, withIntermediateDirectories: true)
        try fm.createDirectory(at: small, withIntermediateDirectories: true)
        for index in 0..<20 { _ = fm.createFile(atPath: big.appendingPathComponent("\(index)").path, contents: Data([1])) }
        _ = fm.createFile(atPath: small.appendingPathComponent("file").path, contents: Data([2]))
        let fair = ScanRecord()
        try await StorageScan.run(roots: [big.path, small.path], limit: 8) { await fair.accept($0) }
        let fairNodes = await fair.nodes
        check(fairNodes.count <= 8 && fairNodes[big.path]?.measurement == .partial, "Global entry bound maintained")
        check(fairNodes[small.path]?.measurement == .complete && fairNodes[small.appendingPathComponent("file").path] != nil, "Later root gets a fair share")
        check(fairNodes[small.appendingPathComponent("file").path]?.modifiedAt != nil, "Scanner collects modification date")
        var known = node("Applications/Xcode.app", type: .package); known.bundleID = "com.apple.dt.Xcode"
        check(ItemKnowledge.explanation(for: known, home: home).source?.host == "developer.apple.com", "Known app explanation links official source")
        known.bundleID = "com.apple.dt.Xcode.fake"
        check(ItemKnowledge.explanation(for: known, home: home).source == nil, "No substring app identity match")

        if CommandLine.arguments.contains("--trash") {
            let app = root.appendingPathComponent("Disposable-\(UUID().uuidString).app")
            try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let plist = ["CFBundleIdentifier": "io.uncomew.disposable.test", "CFBundleName": "Disposable", "CFBundlePackageType": "APPL"]
            let payload = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try payload.write(to: app.appendingPathComponent("Contents/Info.plist"))
            let candidate = RemovalSafety.capture(path: app.path, allowedParent: root.path, bytes: Int64(payload.count), isApplication: true)!
            guard let receipt = try TrashService.move(candidate) else { fatalError("OS did not return a restorable path") }
            check(!fm.fileExists(atPath: app.path), "Disposable app moved into real OS Trash")
            try Data([7]).write(to: app)
            do { try TrashService.restore(receipt); fatalError("Overwrote occupied destination") }
            catch TrashService.Failure.occupied { checks += 1 }
            let retained = try Data(contentsOf: app)
            check(retained == Data([7]), "Conflicting file preserved")
            try fm.removeItem(at: app) // Only the test's own conflict file.
            try TrashService.restore(receipt)
            let restored = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            check(restored == payload && FileIdentity.read(app.path) == candidate.identity, "App identity and contents restored")
            check(!fm.fileExists(atPath: receipt.trashedPath), "No disposable app left in Trash")
            do { try TrashService.restore(receipt); fatalError("Restored twice") }
            catch { checks += 1 }
        }
        if CommandLine.arguments.contains("--benchmark") {
            let bench = root.appendingPathComponent("benchmark")
            try fm.createDirectory(at: bench, withIntermediateDirectories: true)
            for group in 0..<200 {
                let folder = bench.appendingPathComponent("group-\(group)")
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                for item in 0..<100 { _ = fm.createFile(atPath: folder.appendingPathComponent("file-\(item)").path, contents: nil) }
            }
            let record = ScanRecord(), start = Date()
            try await StorageScan.run(roots: [bench.path]) { await record.accept($0) }
            let elapsed = Date().timeIntervalSince(start)
            let first = await record.first!.timeIntervalSince(start)
            check(await record.nodes.count == 20_201, "20k-file scan enumerates every item")
            let cancelStart = Date()
            let cancelled = Task {
                try await StorageScan.run(roots: [bench.path]) { _ in withUnsafeCurrentTask { $0?.cancel() } }
            }
            do { try await cancelled.value; fatalError("Cancellation ignored") } catch is CancellationError { checks += 1 }
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print(String(format: "Benchmark: 20,201 nodes, first %.3fs, complete %.3fs, cancellation %.3fs, process peak RSS %.1f MB (includes fixtures/tests).", first, elapsed, Date().timeIntervalSince(cancelStart), Double(usage.ru_maxrss) / 1_000_000))
        }
        print("Passed \(checks) improvement checks. Trash only when --trash is explicitly supplied; disposable fixture only.")
    }
}
