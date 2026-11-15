import AppKit
import Foundation

@MainActor
final class StorageAnalyzer: ObservableObject {
    typealias ScanOperation = @Sendable ([String], @escaping @Sendable (ScanBatch) async -> Void) async throws -> Void
    private let runScan: ScanOperation
    private let decisionStore: CandidateDecisionStore
    init(decisionDefaults: UserDefaults = .standard, runScan: @escaping ScanOperation = { roots, publish in
        try await StorageScan.run(roots: roots, publish: publish)
    }) { self.runScan = runScan; self.decisionStore = CandidateDecisionStore(defaults: decisionDefaults) }
    enum State: Equatable {
        case idle, scanning(String), finished(Date), cancelled, failed(String)
    }
    enum BrowseMode: String, CaseIterable { case tree = "폴더 트리", folders = "큰 폴더", files = "큰 파일" }
    @Published private(set) var state: State = .idle
    @Published private(set) var summary = DiskSummary()
    @Published private(set) var capacityLoaded = false
    @Published private(set) var capacityError: String?
    @Published private(set) var nodes: [String: StorageNode] = [:]
    @Published private(set) var issueCount = 0
    @Published private(set) var roots: [String] = []
    @Published private(set) var visited = 0
    @Published private(set) var capacityDate: Date?
    @Published private(set) var initialAvailableBytes: Int64?
    @Published private(set) var resultsNeedRefresh = false
    func markResultsForReview() { if !nodes.isEmpty { resultsNeedRefresh = true } }
    func reanalyze() { analyze(roots: roots.isEmpty ? nil : roots) }
    private var defaultScanRoots: [String] {
        StorageScan.normalizedRoots([FileManager.default.homeDirectoryForCurrentUser.path, "/Applications", "/Library", "/private"])
    }
    private var candidateScanRoots: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return StorageScan.normalizedRoots([home + "/Downloads", "/Applications", home + "/Applications",
                                            home + "/Library/Caches", home + "/Library/Developer/Xcode/DerivedData"])
    }
    private var hasReusableResults: Bool {
        if case .finished = state { return !nodes.isEmpty && !resultsNeedRefresh }
        return false
    }
    var hasDefaultScope: Bool { roots == defaultScanRoots && hasReusableResults }
    var hasCandidateScope: Bool { roots == candidateScanRoots && hasReusableResults }
    @Published private(set) var candidates: [CleanupCandidate] = []
    @Published private(set) var preparingCandidates = false
    @Published private(set) var decisionRevision = 0
    @Published var candidateDecisionFilter = "전체"
    var keptCandidatePaths: Set<String> {
        Set(candidates.filter { decision(for: $0) == .keep }.map(\.id))
    }
    func decision(for candidate: CleanupCandidate) -> CandidateDecision? {
        decisionStore.decision(for: candidate.node)
    }
    func hasChangedDecision(for candidate: CleanupCandidate) -> Bool {
        decisionStore.records[candidate.id] != nil && decision(for: candidate) == nil
    }
    func setDecision(_ decision: CandidateDecision?, for candidate: CleanupCandidate, confirmedQuestions: Set<Int> = []) {
        guard !isScanning, !preparingCandidates, !resultsNeedRefresh,
              candidates.contains(where: { $0.id == candidate.id &&
                  CandidateDecisionStore.fingerprint($0.node) == CandidateDecisionStore.fingerprint(candidate.node) }),
              decision != .review || (candidate.node.measurement == .complete &&
                  confirmedQuestions == Set(candidate.questions.indices)) else { return }
        decisionStore.save(decision, for: candidate.node)
        decisionRevision += 1
        reconcileCandidateSelection()
    }
    @Published var candidateCategory = "전체"
    @Published var selectedCandidatePath: String?
    @Published var showKeptCandidates = false
    @Published var browseSearch = ""
    @Published var browseFileKind: BrowseFileKind = .all
    @Published var browseMinimumSize: BrowseMinimumSize = .all
    @Published var browseFolder: String?
    var browseFilter: StorageBrowseFilter { StorageBrowseFilter(kind: browseFileKind, minimum: browseMinimumSize, folder: browseFolder) }
    var hasBrowseFilters: Bool { !browseSearch.isEmpty || browseFileKind != .all || browseMinimumSize != .all || browseFolder != nil }
    var usesFlatBrowseList: Bool { mode != .tree || hasBrowseFilters }
    func browseFiles(in node: StorageNode) {
        guard node.isFolder else { return }
        clearBrowseFilters()
        browseSortByName = false
        browseFolder = node.path
        browseIncludePackages = node.type == .package || node.insidePackage
        mode = .files
        selectedPath = nil
    }
    @Published var browseSortByName = false
    @Published var browseIncludePackages = false
    @Published var browseDisplayLimit = 300
    var visibleCandidates: [CleanupCandidate] {
        candidates.filter {
            (candidateCategory == "전체" || $0.category.rawValue == candidateCategory) &&
            (showKeptCandidates || decision(for: $0) != .keep) &&
            (candidateDecisionFilter == "전체" || decision(for: $0)?.rawValue == candidateDecisionFilter)
        }.sorted {
            let leftLater = decision(for: $0) == .later
            let rightLater = decision(for: $1) == .later
            if leftLater != rightLater { return !leftLater }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return ($0.node.allocatedBytes ?? 0) == ($1.node.allocatedBytes ?? 0)
                ? $0.id < $1.id : ($0.node.allocatedBytes ?? 0) > ($1.node.allocatedBytes ?? 0)
        }
    }
    func reconcileCandidateSelection() {
        let visible = visibleCandidates
        if !visible.contains(where: { $0.id == selectedCandidatePath }) { selectedCandidatePath = visible.first?.id }
    }
    func clearBrowseFilters() {
        browseSearch = ""; browseIncludePackages = false; browseDisplayLimit = 300
        browseFileKind = .all; browseMinimumSize = .all; browseFolder = nil
    }
    func analyzeCandidates() {
        analyze(roots: candidateScanRoots)
    }
    func showCurrentRanking(_ target: BrowseMode) {
        clearBrowseFilters()
        browseSortByName = false
        selectedPath = nil
        mode = target
    }
    @Published var mode: BrowseMode = .tree {
        didSet { if mode == .folders { browseFileKind = .all } }
    }
    @Published var selectedPath: String?
    @Published var expanded = Set<String>()
    private var scanTask: Task<Void, Never>?
    private var capacityTask: Task<Void, Never>?
    private var generation = UUID()

    var isScanning: Bool { if case .scanning = state { return true }; return false }
    var statusText: String {
        switch state {
        case .idle: return "아직 상세 분석하지 않았습니다."
        case .scanning(let path): return "\(visited.formatted())개 확인 중 · \(path)"
        case .finished(let date): return "분석 완료 · \(date.formatted(date: .omitted, time: .shortened)) · \(visited.formatted())개 항목"
        case .cancelled: return "분석 중지 · 현재까지 확인한 \(visited.formatted())개 항목을 볼 수 있습니다."
        case .failed(let message): return "분석 실패: \(message)"
        }
    }
    private func hasIssue(_ node: StorageNode) -> Bool {
        node.measurement == .unavailable || node.measurement == .excluded || node.note != nil && node.measurement == .partial
    }
    var suggestsPrivacyAccess: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return nodes.values.contains { node in
            node.permissionDenied && node.measurement == .unavailable && ["\(home)/Library/Mail", "\(home)/Library/Messages", "\(home)/Library/Safari"].contains {
                node.path == $0 || node.path.hasPrefix($0 + "/")
            }
        }
    }

    func refreshCapacity() {
        guard capacityTask == nil else { return }
        capacityTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> Result<DiskSummary, Error> in
                Result {
                    // URL resource values may be cached. Each refresh must query the filesystem anew.
                    var volumeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                    volumeURL.removeAllCachedResourceValues()
                    let value = try volumeURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
                    guard let total = value.volumeTotalCapacity, let available = value.volumeAvailableCapacity else {
                        throw NSError(domain: "Uncomew", code: 1, userInfo: [NSLocalizedDescriptionKey: "용량 정보를 읽을 수 없습니다."])
                    }
                    var summary = DiskSummary()
                    summary.totalBytes = Int64(total)
                    summary.availableBytes = Int64(available)
                    // Read independently so unavailable estimates do not hide the basic free-space value.
                    let estimated = try? volumeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                    summary.importantAvailableBytes = estimated?.volumeAvailableCapacityForImportantUsage
                    return summary
                }
            }.value
            guard let self else { return }
            switch result {
            case .success(let value):
                if self.initialAvailableBytes == nil { self.initialAvailableBytes = value.availableBytes }
                self.summary = value; self.capacityLoaded = true; self.capacityDate = Date(); self.capacityError = nil
            case .failure(let error): self.capacityError = error.localizedDescription
            }
            self.capacityTask = nil
        }
    }

    func analyze(roots requested: [String]? = nil) {
        guard !isScanning else { return }
        roots = StorageScan.normalizedRoots(requested ?? defaultScanRoots)
        resultsNeedRefresh = false
        candidates = []; preparingCandidates = false
        candidateDecisionFilter = "전체"; candidateCategory = "전체"; selectedCandidatePath = nil; showKeptCandidates = false
        clearBrowseFilters()
        nodes = [:]; issueCount = 0; visited = 0; selectedPath = nil; expanded = Set(roots)
        state = .scanning("준비 중")
        refreshCapacity()
        let runID = UUID(); generation = runID
        let scanRoots = roots
        let operation = runScan
        scanTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try await operation(scanRoots) { [weak self] batch in
                    await self?.accept(batch, runID: runID)
                }
                await self?.complete(runID: runID, cancelled: Task.isCancelled)
            } catch is CancellationError {
                await self?.complete(runID: runID, cancelled: true)
            } catch {
                await self?.fail(error.localizedDescription, runID: runID)
            }
        }
    }

    private func accept(_ batch: ScanBatch, runID: UUID) {
        guard runID == generation else { return }
        var issues = issueCount
        for node in batch.nodes {
            if let previous = nodes[node.path], hasIssue(previous) { issues -= 1 }
            if hasIssue(node) { issues += 1 }
        }
        nodes.merge(batch.nodes.lazy.map { ($0.path, $0) }) { _, latest in latest }
        issueCount = issues
        visited = batch.visited
        state = .scanning(batch.currentPath)
    }
    private func complete(runID: UUID, cancelled: Bool) {
        guard runID == generation else { return }
        var completed = nodes
        var didChange = false
        for (path, node) in nodes where node.measurement == .scanning {
            var partial = node
            partial.measurement = .partial
            completed[path] = partial
            didChange = true
        }
        if didChange { nodes = completed }
        state = cancelled ? .cancelled : .finished(Date())
        scanTask = nil
        refreshCapacity()
        preparingCandidates = true
        let snapshot = Array(nodes.values)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        Task {
            let found = await Task.detached(priority: .utility) {
                CleanupAdvisor.candidates(in: snapshot, home: home)
            }.value
            guard runID == generation else { return }
            candidates = found
            preparingCandidates = false
            reconcileCandidateSelection()
        }
    }
    private func fail(_ message: String, runID: UUID) {
        guard runID == generation else { return }
        state = .failed(message); scanTask = nil
    }
    func cancel() { scanTask?.cancel() }
    @discardableResult func chooseFolder() -> Bool {
        guard !isScanning else { return false }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "이 폴더 안의 메타데이터를 분석합니다. 파일 내용을 열거나 삭제하지 않습니다."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        analyze(roots: [url.path])
        mode = .tree
        browseSortByName = false
        return true
    }
    func showInTree(_ node: StorageNode) {
        mode = .tree
        clearBrowseFilters()
        if node.insidePackage { browseIncludePackages = true }
        selectedPath = node.path
        var path = node.parent
        while let current = path {
            expanded.insert(current)
            path = nodes[current]?.parent
        }
    }
    func reveal(path: String) {
        guard !ItemKnowledge.isSystemManaged(path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
    func reveal(_ item: StorageItem) { if item.canRevealInFinder { reveal(path: item.path) } }
    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}
