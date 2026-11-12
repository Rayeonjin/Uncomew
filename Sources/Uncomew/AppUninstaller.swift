import AppKit
import Foundation
import UniformTypeIdentifiers

struct RelatedFile: Identifiable {
    var id: String { path }
    let path: String
    let bytes: Int64
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
struct ApplicationEntry: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    var lastUsedDate: Date? = nil
    var reviewKey: String { bundleID + "|" + url.standardizedFileURL.path }
}
enum ApplicationUsage {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "모든 앱", older90 = "90일 이상 · 큰 앱", older180 = "180일 이상 · 큰 앱", unknown = "사용 기록 확인 불가"
        var id: String { rawValue }
    }
    static func validatedDate(_ date: Date?, now: Date = Date()) -> Date? {
        guard let date, date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 > 0, date <= now else { return nil }
        return date
    }
    static func lastUsed(_ url: URL) -> Date? {
        validatedDate(NSMetadataItem(url: url)?.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date)
    }
    static func matches(_ app: ApplicationEntry, filter: Filter, bytes: Int64?, kept: Bool,
                        running: Bool, now: Date = Date()) -> Bool {
        if filter == .all { return true }
        let last = validatedDate(app.lastUsedDate, now: now)
        if filter == .unknown { return last == nil }
        guard !kept, !running, let last, let bytes, bytes >= 100_000_000 else { return false }
        let days = filter == .older180 ? 180 : 90
        return now.timeIntervalSince(last) >= Double(days) * 86_400
    }
}
enum ApplicationRanking {
    static func sorted(_ apps: [ApplicationEntry], nodes: [String: StorageNode], largestFirst: Bool) -> [ApplicationEntry] {
        apps.sorted {
            let left = nodes[$0.url.path]?.allocatedBytes
            let right = nodes[$1.url.path]?.allocatedBytes
            if largestFirst && left != right { return (left ?? -1) > (right ?? -1) }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.url.path < $1.url.path : order == .orderedAscending
        }
    }
}
struct TrashPlan: Identifiable {
    let id = UUID()
    let candidates: [RemovalCandidate]
    var bytes: Int64 { candidates.reduce(0) { $0 + $1.bytes } }
}

@MainActor
final class AppUninstaller: ObservableObject {
    private let preferences: UserDefaults
    @Published private(set) var keptApplicationKeys: Set<String>
    @Published var inventorySearch = "" {
        didSet { if inventorySearch != oldValue { includeApplication = false } }
    }
    @Published var inventoryLargestFirst = true
    @Published var usageFilter: ApplicationUsage.Filter = .all {
        didSet { if usageFilter != oldValue { includeApplication = false } }
    }
    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        keptApplicationKeys = Set(preferences.stringArray(forKey: "applicationReviewExclusions.v1") ?? [])
    }
    func isKept(_ app: ApplicationEntry) -> Bool { keptApplicationKeys.contains(app.reviewKey) }
    func setKept(_ kept: Bool, app: ApplicationEntry) {
        if kept { keptApplicationKeys.insert(app.reviewKey) } else { keptApplicationKeys.remove(app.reviewKey) }
        preferences.set(keptApplicationKeys.sorted(), forKey: "applicationReviewExclusions.v1")
        if selectedAppURL == app.url { includeApplication = false; review = nil }
    }
    @Published private(set) var selectedAppURL: URL?
    @Published private(set) var appName = ""
    @Published private(set) var bundleIdentifier = ""
    @Published private(set) var appSize: Int64?
    @Published private(set) var relatedFiles: [RelatedFile] = []
    @Published var includeApplication = false
    @Published var review: TrashPlan?
    @Published private(set) var applications: [ApplicationEntry] = []
    @Published private(set) var inventoryLoading = false
    @Published private(set) var isScanning = false
    @Published private(set) var isTrashing = false
    @Published var statusMessage: String?
    @Published private(set) var removalRevision = 0
    @Published private(set) var restorableItems: [TrashReceipt] = []
    private typealias ScanResult = (String, RemovalCandidate?, [RelatedFile], [String], Int64?)
    private var scanTask: Task<ScanResult, Never>?
    func cancelScan() { scanTask?.cancel() }
    private var appCandidate: RemovalCandidate?
    var busy: Bool { isScanning || isTrashing || review != nil }

    func loadApplications() {
        guard !inventoryLoading else { return }
        inventoryLoading = true
        Task {
            applications = await Task.detached(priority: .utility) {
                let fm = FileManager.default
                let roots = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
                var found: [ApplicationEntry] = []
                func collect(_ root: URL, depth: Int) {
                    guard depth <= 2, let urls = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
                    for url in urls {
                        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { continue }
                        if url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url) {
                            found.append(ApplicationEntry(url: url, name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent, bundleID: bundle.bundleIdentifier ?? "", lastUsedDate: ApplicationUsage.lastUsed(url)))
                        } else if values.isDirectory == true { collect(url, depth: depth + 1) }
                    }
                }
                for root in roots { collect(root, depth: 0) }
                return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }.value
            inventoryLoading = false
        }
    }
    func chooseApplication() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "분석할 앱 선택"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }
    func scan(_ url: URL) {
        guard !busy else { return }
        includeApplication = false; relatedFiles = []; appCandidate = nil; appSize = nil
        selectedAppURL = url; appName = url.deletingPathExtension().lastPathComponent; bundleIdentifier = ""
        statusMessage = nil; isScanning = true
        let work = Task.detached(priority: .utility) { () -> ScanResult in
                let id = Bundle(url: url)?.bundleIdentifier ?? ""
                let measurement = DirectoryMeasurement.measure(url.path)
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let app: RemovalCandidate? = measurement.bytes.flatMap { bytes -> RemovalCandidate? in
                    guard RemovalSafety.approvedInstalledApp(url.path, home: home) else { return nil }
                    return RemovalSafety.capture(path: url.path, allowedParent: url.deletingLastPathComponent().path,
                                                 bytes: bytes, isApplication: true)
                }
                var files: [RelatedFile] = []
                var notes: [String] = []
                if !measurement.warnings.isEmpty { notes.append("앱 크기는 일부만 측정됐거나 확인할 수 없습니다.") }
                for match in RemovalSafety.relatedPaths(bundleID: id, home: home) {
                    if Task.isCancelled { break }
                    guard RemovalSafety.noSymlinkAncestors(match.path) else { continue }
                    let size = DirectoryMeasurement.measure(match.path)
                    guard let bytes = size.bytes,
                          RemovalSafety.capture(path: match.path, allowedParent: match.parent, bytes: bytes) != nil else { continue }
                    files.append(RelatedFile(path: match.path, bytes: bytes))
                    if !size.warnings.isEmpty { notes.append("일부 측정: \(match.path)") }
                }
                return (id, app, files, notes, measurement.bytes)
        }
        scanTask = work
        Task {
            let result = await work.value
            scanTask = nil
            if work.isCancelled {
                isScanning = false
                statusMessage = "앱 분석을 중지했습니다. 다른 앱을 선택하거나 같은 앱을 다시 분석할 수 있습니다."
                return
            }
            bundleIdentifier = result.0; appCandidate = result.1; appSize = result.4
            relatedFiles = result.2.sorted { $0.bytes > $1.bytes }; isScanning = false
            var notes = result.3
            if appCandidate == nil { notes.append("표준 Applications 위치가 아니거나 앱 크기·경로를 확인하지 못해 앱 안에서 이동할 수 없습니다. Finder에서 위치를 확인하세요.") }
            if !ItemKnowledge.validBundleID(bundleIdentifier) { notes.append("유효한 Bundle ID가 없어 관련 파일을 추정하지 않았습니다.") }
            statusMessage = notes.isEmpty ? nil : notes.joined(separator: "\n")
        }
    }
    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
    var canSelectApplication: Bool { appCandidate != nil }
    func prepareReview() {
        guard !busy else { return }
        guard includeApplication, let appCandidate,
              selectedAppURL?.path == appCandidate.path,
              RemovalSafety.approvedInstalledApp(appCandidate.path, home: FileManager.default.homeDirectoryForCurrentUser.path),
              RemovalSafety.isStillValid(appCandidate) else {
            statusMessage = "앱 위치나 파일 식별 정보가 바뀌었습니다. 다시 분석하세요."
            return
        }
        review = TrashPlan(candidates: [appCandidate])
    }
    func restore(_ receipt: TrashReceipt) {
        guard !busy, restorableItems.contains(where: { $0.id == receipt.id }) else { return }
        isTrashing = true
        Task {
            let error = await Task.detached(priority: .userInitiated) { () -> String? in
                do { try TrashService.restore(receipt); return nil }
                catch { return error.localizedDescription }
            }.value
            isTrashing = false
            if let error { statusMessage = "복원하지 못했습니다: \(error)" }
            else {
                restorableItems.removeAll { $0.id == receipt.id }
                removalRevision += 1
                statusMessage = "복원 완료: \(receipt.originalPath)\n앱을 다시 선택해 현재 크기와 관련 파일을 확인하세요."
                includeApplication = false; appCandidate = nil; relatedFiles = []
                loadApplications()
            }
        }
    }
    func moveReviewedToTrash(confirmedFilename: String) {
        guard let plan = review, !isScanning, !isTrashing else { return }
        review = nil
        guard plan.candidates.count == 1, let candidate = plan.candidates.first,
              candidate.isApplication, selectedAppURL?.path == candidate.path,
              URL(fileURLWithPath: candidate.path).lastPathComponent == confirmedFilename,
              RemovalSafety.approvedInstalledApp(candidate.path, home: FileManager.default.homeDirectoryForCurrentUser.path),
              RemovalSafety.isStillValid(candidate) else {
            statusMessage = "확인한 앱 파일명·위치 또는 파일 식별 정보가 일치하지 않습니다. 이동하지 않았습니다."
            return
        }
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL == selectedAppURL?.standardizedFileURL ||
                (!bundleIdentifier.isEmpty && $0.bundleIdentifier == bundleIdentifier)
        }
        guard !running else { statusMessage = "해당 앱이 실행 중입니다. 먼저 종료한 뒤 다시 확인하세요."; return }
        isTrashing = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([String], [String], [TrashReceipt]) in
                var success: [String] = []; var failures: [String] = []; var receipts: [TrashReceipt] = []
                for candidate in plan.candidates {
                    guard RemovalSafety.isStillValid(candidate) else {
                        failures.append("\(candidate.path): 항목이 바뀌었거나 없어졌습니다. 다시 분석하세요."); continue
                    }
                    do {
                        if let receipt = try TrashService.move(candidate) { receipts.append(receipt) }
                        success.append(candidate.path)
                    } catch { failures.append("\(candidate.path): \(error.localizedDescription)") }
                }
                return (success, failures, receipts)
            }.value
            isTrashing = false
            restorableItems.append(contentsOf: result.2)
            if !result.0.isEmpty { removalRevision += 1 }
            relatedFiles.removeAll { result.0.contains($0.path) }
            if let path = selectedAppURL?.path, result.0.contains(path) {
                appCandidate = nil; includeApplication = false; applications.removeAll { $0.url.path == path }
            }
            statusMessage = "휴지통 이동 \(result.0.count)개 · 실패 \(result.1.count)개\n" +
                result.0.map { "이동: \($0)" }.joined(separator: "\n") + "\n" + result.1.joined(separator: "\n") +
                "\n앱 내 복원 가능 \(result.2.count)개. 복원 항목이 없으면 Finder의 휴지통에서 확인하세요." +
                "\n휴지통을 비우기 전까지 공간을 차지할 수 있습니다. 요약에서 남은 공간을 다시 확인하세요."
        }
    }
}
