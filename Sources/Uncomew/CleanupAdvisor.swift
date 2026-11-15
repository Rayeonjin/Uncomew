import Foundation

struct CleanupCandidate: Identifiable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case installers = "설치 파일", downloads = "오래된 다운로드", archives = "압축 파일"
        case builds = "빌드 작업 데이터", caches = "앱 캐시", applications = "큰 앱"
    }
    var id: String { node.path }
    let node: StorageNode
    let category: Category
    let reason: String
    let impact: String
    let nextStep: String
}

// Review suggestions only. No file-content inspection, deletion decision, or reclaimable-space total.
enum CleanupAdvisor {
    static func candidate(for node: StorageNode, home: String, now: Date = Date()) -> CleanupCandidate? {
        guard node.measurement == .complete || node.measurement == .partial,
              let bytes = node.allocatedBytes, bytes >= 20_000_000,
              !node.insidePackage, node.linkCount <= 1,
              node.type == .file || node.isFolder,
              !ItemKnowledge.isSystemManaged(node.path),
              !ItemKnowledge.within(node.path, home + "/Library/CloudStorage"),
              !ItemKnowledge.within(node.path, home + "/Library/Mobile Documents") else { return nil }
        func result(_ category: CleanupCandidate.Category, _ reason: String, _ impact: String, _ next: String) -> CleanupCandidate {
            CleanupCandidate(node: node, category: category, reason: reason, impact: impact, nextStep: next)
        }
        let url = URL(fileURLWithPath: node.path)
        let downloads = ItemKnowledge.within(node.path, home + "/Downloads")
        if downloads && node.type == .file {
            if ["dmg", "pkg", "mpkg", "iso"].contains(url.pathExtension.lowercased()) {
                return result(.installers, "다운로드 폴더의 설치·디스크 이미지 형식이며 20 MB 이상입니다. 설치 완료 여부는 확인하지 않았습니다.", "다시 설치할 때 원본이 필요할 수 있습니다. 디스크 이미지에 개인 자료가 있을 수도 있습니다.", "설치가 끝났고 다시 받을 수 있는지 확인한 뒤 Finder에서 검토하세요.")
            }
            if let date = node.modifiedAt, now.timeIntervalSince(date) >= 90 * 86_400 {
                return result(.downloads, "다운로드 폴더에서 마지막 수정 후 90일 이상 지났고 20 MB 이상입니다. 마지막 사용 시각을 뜻하지 않습니다.", "오래된 파일도 계약서·사진 등 필요한 원본일 수 있습니다.", "내용과 별도 보관본을 확인한 뒤 Finder에서 검토하세요.")
            }
            if bytes >= 100_000_000 && ["zip", "7z", "rar", "tar", "gz", "xz"].contains(url.pathExtension.lowercased()) {
                return result(.archives, "다운로드 폴더의 압축 파일이며 100 MB 이상입니다. 압축 해제 여부는 확인하지 않았습니다.", "유일한 원본이나 백업일 수 있습니다.", "압축 내용과 원본 보관 여부를 확인하세요.")
            }
        }
        if node.path == home + "/Library/Developer/Xcode/DerivedData" {
            return result(.builds, "Xcode의 DerivedData 경로이며 20 MB 이상입니다. 프로젝트 원본 위치를 검사한 결과는 아닙니다.", "빌드 중간 결과·인덱스를 다시 만드는 데 시간이 걸릴 수 있습니다.", "Xcode 작업을 마친 뒤 프로젝트별 내용을 Finder에서 검토하세요.")
        }
        if url.deletingLastPathComponent().path == home + "/Library/Caches" {
            return result(.caches, "사용자 Library/Caches 바로 아래의 항목이며 20 MB 이상입니다.", "앱이 다시 다운로드하거나 생성할 수 있어 확보 효과가 일시적일 수 있습니다. 경로만으로 내용의 안전성을 보장하지 않습니다.", "소유 앱의 캐시 관리 기능을 먼저 확인하세요. 사용 중인 앱의 데이터를 일괄 삭제하지 마세요.")
        }
        if node.type == .package && url.pathExtension.lowercased() == "app" && bytes >= 100_000_000 {
            return result(.applications, "앱 본체가 100 MB 이상입니다. 사용 빈도나 불필요 여부는 판단하지 않았습니다.", "앱 본체 크기이며 관련 문서·콘텐츠 크기는 별도입니다.", "앱 관리에서 용도와 관련 경로를 확인하고 선택 항목만 검토하세요.")
        }
        return nil
    }
    static func candidates(in nodes: [StorageNode], home: String, now: Date = Date()) -> [CleanupCandidate] {
        let found = nodes.compactMap { candidate(for: $0, home: home, now: now) }
        let paths = Set(found.map(\.id))
        return found.filter { candidate in
            var parent = URL(fileURLWithPath: candidate.id).deletingLastPathComponent()
            while parent.path != "/" {
                if paths.contains(parent.path) { return false }
                parent.deleteLastPathComponent()
            }
            return true
        }.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.node.allocatedBytes != $1.node.allocatedBytes { return ($0.node.allocatedBytes ?? 0) > ($1.node.allocatedBytes ?? 0) }
            return $0.id < $1.id
        }
    }
}

// Decisions are local review notes, never authorization to delete.
enum CandidateDecision: String, Codable, CaseIterable {
    case keep = "계속 보관", later = "나중에 검토", review = "정리 검토"
}

struct CandidateDecisionRecord: Codable {
    let decision: CandidateDecision
    let fingerprint: String
    let savedAt: Date
}

final class CandidateDecisionStore {
    private let defaults: UserDefaults
    private let key = "Uncomew.candidateDecisions.v1"
    private(set) var records: [String: CandidateDecisionRecord]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = defaults.data(forKey: key).flatMap {
            try? JSONDecoder().decode([String: CandidateDecisionRecord].self, from: $0)
        } ?? [:]
    }
    static func fingerprint(_ node: StorageNode) -> String {
        // Snapshot evidence only: a changed identity, timestamp, size or completeness
        // requires a new decision. Folder notes do not apply to individual children.
        [node.fileIdentity ?? "unknown", node.type.rawValue,
         node.modifiedAt.map { String($0.timeIntervalSince1970) } ?? "unknown",
         node.allocatedBytes.map(String.init) ?? "unknown",
         node.logicalBytes.map(String.init) ?? "unknown", node.measurement.rawValue,
         String(node.linkCount)].joined(separator: "|")
    }
    func decision(for node: StorageNode) -> CandidateDecision? {
        guard let record = records[node.path],
              record.fingerprint == Self.fingerprint(node) else { return nil }
        return record.decision
    }
    func save(_ decision: CandidateDecision?, for node: StorageNode) {
        if let decision {
            records[node.path] = CandidateDecisionRecord(decision: decision,
                fingerprint: Self.fingerprint(node), savedAt: Date())
        } else { records.removeValue(forKey: node.path) }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }
}

extension CleanupCandidate {
    var priority: Int {
        if node.measurement != .complete { return 4 }
        switch category {
        case .installers: return 0
        case .builds: return 1
        case .applications: return 2
        case .archives, .downloads, .caches: return 3
        }
    }
    var priorityReason: String {
        if node.measurement != .complete { return "일부만 분석됨 · 먼저 다시 분석하세요" }
        switch category {
        case .installers: return "설치 완료 여부부터 확인"
        case .builds: return "진행 중인 작업과 프로젝트 원본 확인"
        case .applications: return "사용 여부와 앱 안의 자료 확인"
        case .archives: return "유일한 원본·백업인지 확인"
        case .downloads: return "오래된 파일 · 내용 확인 필요"
        case .caches: return "소유 앱의 정리 기능부터 확인"
        }
    }
    var questions: [String] {
        switch category {
        case .installers:
            return ["이 파일로 필요한 설치를 마쳤나요?", "개인 자료가 든 이미지가 아니며, 필요하면 다시 구할 수 있나요?"]
        case .builds:
            return ["Xcode의 빌드·실행 작업을 모두 마쳤나요?", "이 폴더에 필요한 원본을 따로 넣어두지 않았는지 확인했나요?", "빌드 결과와 인덱스를 다시 만드는 시간을 감수할 수 있나요?"]
        case .applications:
            return ["당분간 이 앱을 쓰지 않아도 되나요?", "앱 본체 안의 필요한 자료를 별도로 보관했나요?", "다시 설치할 방법과 필요한 라이선스를 확보했나요?"]
        case .archives:
            return ["압축 파일 안의 내용을 확인했나요?", "필요한 내용이 다른 곳에 있으며, 유일한 원본이나 백업이 아닌가요?"]
        case .downloads:
            return ["파일 내용을 확인했고 더 이상 필요하지 않나요?", "필요한 원본이나 백업을 잃는 일이 없는지 확인했나요?"]
        case .caches:
            return ["어떤 앱이 사용하는 데이터인지 확인했나요?", "해당 앱의 캐시 정리 기능과 안내를 확인했나요?", "오프라인 자료가 사라지거나 다시 다운로드될 수 있음을 확인했나요?"]
        }
    }
}
