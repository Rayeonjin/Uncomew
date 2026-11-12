import Foundation

@main
struct FlowTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["UNCOMEW_TEST_ROOT"] ?? fm.currentDirectoryPath).appendingPathComponent(".build/flow-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        var file = StorageNode(path: "/fixture/photos/CLIP.MOV", parent: "/fixture/photos", type: .file, insidePackage: false, allocatedBytes: 100_000_000)
        let videoFilter = StorageBrowseFilter(kind: .video, minimum: .mb100, folder: "/fixture/photos")
        check(videoFilter.matches(file), "Combined filter accepts uppercase video at exact size boundary")
        file.allocatedBytes = nil
        check(!videoFilter.matches(file), "Unknown size cannot pass a minimum-size filter")
        file.allocatedBytes = 99_999_999
        check(!videoFilter.matches(file), "Below-threshold allocated bytes are excluded")
        let neighbor = StorageNode(path: "/fixture/photos-old/clip.mov", parent: "/fixture/photos-old", type: .file, insidePackage: false, allocatedBytes: 200_000_000)
        check(!videoFilter.matches(neighbor), "Folder scope cannot include sibling with same prefix")
        let package = StorageNode(path: "/fixture/photos/library.mov", parent: "/fixture/photos", type: .package, insidePackage: false, allocatedBytes: 200_000_000)
        check(!videoFilter.matches(package), "Package extension is not evidence of an individual video")
        check(BrowseFileKind.classify(path: "/fixture/no-extension") == .other, "Unknown extensions remain other")
        let navigation = StorageAnalyzer()
        navigation.browseFileKind = .video; navigation.browseMinimumSize = .gb1; navigation.browseSearch = "old"
        navigation.browseSortByName = true
        navigation.browseFiles(in: package)
        check(navigation.mode == .files && navigation.browseFolder == package.path && navigation.browseIncludePackages, "Explicit package drilldown enables internal files")
        check(navigation.browseFileKind == .all && navigation.browseMinimumSize == .all && navigation.browseSearch.isEmpty, "Drilldown clears incompatible filters")
        navigation.showInTree(package)
        check(!navigation.hasBrowseFilters && navigation.mode == .tree && navigation.selectedPath == package.path, "Tree return clears filters and restores location")
        navigation.browseSortByName = true
        navigation.browseFolder = "/fixture/photos"
        navigation.browseFileKind = .video
        navigation.browseMinimumSize = .gb1
        navigation.browseSearch = "missing"
        navigation.showCurrentRanking(.files)
        check(!navigation.hasBrowseFilters && !navigation.browseSortByName && navigation.selectedPath == nil, "Current-scope ranking clears old folder, search, size and ordering")
        navigation.browseFileKind = .video
        navigation.mode = .folders
        check(navigation.browseFileKind == .all, "Folder mode cannot retain a hidden file-kind filter without a mounted view")
        navigation.browseSortByName = true
        navigation.browseFiles(in: package)
        check(!navigation.browseSortByName, "Large-files drilldown always starts in size order")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var oldApp = ApplicationEntry(url: URL(fileURLWithPath: "/Applications/UsageFixture.app"), name: "Fixture", bundleID: "io.uncomew.usagefixture", lastUsedDate: now.addingTimeInterval(-90 * 86_400))
        func matches(_ app: ApplicationEntry, _ filter: ApplicationUsage.Filter, bytes: Int64? = 100_000_000,
                     kept: Bool = false, running: Bool = false) -> Bool {
            ApplicationUsage.matches(app, filter: filter, bytes: bytes, kept: kept, running: running, now: now)
        }
        check(matches(oldApp, .older90), "90-day boundary is included")
        check(!matches(oldApp, .older180), "90-day history is not 180-day history")
        check(!matches(oldApp, .older90, bytes: nil) && !matches(oldApp, .older90, bytes: 99_999_999), "Unknown/small sizes are not old large-app candidates")
        check(!matches(oldApp, .older90, kept: true) && !matches(oldApp, .older90, running: true), "Kept and running apps are excluded")
        oldApp.lastUsedDate = now.addingTimeInterval(-180 * 86_400)
        check(matches(oldApp, .older180), "180-day boundary is included")
        oldApp.lastUsedDate = now.addingTimeInterval(-10)
        check(!matches(oldApp, .older90), "Recently opened apps are excluded")
        oldApp.lastUsedDate = nil
        check(matches(oldApp, .unknown) && !matches(oldApp, .older90), "Missing history never implies unused")
        oldApp.lastUsedDate = now.addingTimeInterval(1)
        check(matches(oldApp, .unknown) && !matches(oldApp, .older90), "Future dates are unknown")
        check(ApplicationUsage.validatedDate(Date(timeIntervalSince1970: 0), now: now) == nil, "Epoch placeholder is unknown")
        let suite = "Uncomew.UsageTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let preferenceModel = AppUninstaller(preferences: preferences)
        preferenceModel.includeApplication = true
        preferenceModel.inventorySearch = "some-other-app"
        check(!preferenceModel.includeApplication, "Changing app search clears prior removal selection")
        preferenceModel.includeApplication = true
        preferenceModel.usageFilter = .older180
        check(!preferenceModel.includeApplication, "Changing usage category clears prior removal selection")
        check(preferenceModel.inventorySearch == "some-other-app", "App search lives in the session model across view recreation")
        preferenceModel.setKept(true, app: oldApp)
        check(AppUninstaller(preferences: preferences).isKept(oldApp), "Keep preference survives a new model session")
        preferenceModel.setKept(false, app: oldApp)
        check(!AppUninstaller(preferences: preferences).isKept(oldApp), "Keep preference can be reversed")
        func waitUntil(_ predicate: () -> Bool) async throws {
            for _ in 0..<1000 {
                if predicate() { return }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            preconditionFailure("Async operation failed to finish")
        }
        func fixture(_ name: String) throws -> URL {
            let app = root.appendingPathComponent(name + ".app")
            try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let plist = ["CFBundleIdentifier": "io.uncomew.fixture." + name, "CFBundleName": name, "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
            return app
        }
        let first = try fixture("first"), second = try fixture("second")
        let analyzer = StorageAnalyzer()
        analyzer.analyze(roots: [root.path])
        try await waitUntil { !analyzer.isScanning }
        check(analyzer.nodes[first.standardizedFileURL.path]?.type == .package, "Storage discovers the app for handoff")
        analyzer.markResultsForReview()
        check(analyzer.resultsNeedRefresh, "External changes mark result snapshot")
        analyzer.reanalyze()
        try await waitUntil { !analyzer.isScanning }
        check(analyzer.roots == [root.standardizedFileURL.path], "Refresh preserves selected scope")
        check(!analyzer.resultsNeedRefresh, "New scan clears stale notice")
        try await waitUntil { analyzer.initialAvailableBytes != nil }
        let initial = analyzer.initialAvailableBytes
        analyzer.refreshCapacity()
        check(analyzer.initialAvailableBytes == initial, "Capacity comparison baseline is retained")
        var measured = analyzer.nodes[first.standardizedFileURL.path]!
        measured.allocatedBytes = 123; measured.measurement = .partial
        let entries = [ApplicationEntry(url: second, name: "A", bundleID: "test.second"), ApplicationEntry(url: first, name: "Z", bundleID: "test.first")]
        check(ApplicationRanking.sorted(entries, nodes: [first.path: measured], largestFirst: true).first?.url == first, "Measured apps sort before unknown sizes")
        check(ApplicationRanking.sorted(entries, nodes: [first.path: measured], largestFirst: false).first?.url == second, "Name sorting remains available")
        check(measured.sizeText.contains("일부"), "App size ranking preserves partial label")
        try await waitUntil { !analyzer.preparingCandidates }
        let uninstaller = AppUninstaller()
        uninstaller.scan(first)
        try await waitUntil { !uninstaller.isScanning }
        check(uninstaller.selectedAppURL == first && !uninstaller.canSelectApplication, "App outside Applications is inspection-only")
        check(!uninstaller.includeApplication, "Handoff never preselects removal")
        uninstaller.includeApplication = true
        uninstaller.prepareReview()
        check(uninstaller.review == nil, "Out-of-scope app cannot form a Trash plan")
        let forged = RemovalSafety.capture(path: first.path, allowedParent: root.path, bytes: 1, isApplication: true)!
        uninstaller.review = TrashPlan(candidates: [forged])
        uninstaller.moveReviewedToTrash(confirmedFilename: first.lastPathComponent)
        check(fm.fileExists(atPath: first.path), "Forged review cannot bypass location policy")
        uninstaller.scan(second)
        check(!uninstaller.includeApplication, "Switching apps resets selections")
        uninstaller.cancelScan()
        try await waitUntil { !uninstaller.isScanning }
        check(!uninstaller.busy && !uninstaller.canSelectApplication && uninstaller.statusMessage?.contains("중지") == true, "Cancelled analysis unlocks UI without removable partial targets")
        uninstaller.scan(second)
        try await waitUntil { !uninstaller.isScanning }
        check(!uninstaller.busy && uninstaller.selectedAppURL == second, "Analysis can restart after cancellation")
        print("Passed \(checks) flow checks. No Trash operation performed.")
    }
}
