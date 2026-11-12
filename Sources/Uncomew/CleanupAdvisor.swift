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
            if $0.node.allocatedBytes != $1.node.allocatedBytes { return ($0.node.allocatedBytes ?? 0) > ($1.node.allocatedBytes ?? 0) }
            return $0.id < $1.id
        }
    }
}
