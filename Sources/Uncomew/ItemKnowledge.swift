import Foundation

struct ItemExplanation {
    let title: String
    let purpose: String
    let impact: String
    let evidence: String
    var searchQuery: String?
    var source: URL?
}

enum ItemKnowledge {
    static func isSystemManaged(_ path: String) -> Bool {
        ["/System", "/private/var/vm", "/dev", "/Volumes/Preboot"].contains { within(path, $0) }
    }
    static func within(_ path: String, _ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }
    static func validBundleID(_ id: String) -> Bool {
        id.count <= 200 && id.contains(".") && id.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }
    }
    static func searchURL(query: String) -> URL? {
        var parts = URLComponents(string: "https://www.google.com/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        return parts.url
    }
    private static let appCatalog: [String: (String, String, String, String)] = [
        "com.apple.dt.Xcode": ("Xcode · 앱 개발 도구", "Apple 플랫폼의 앱을 개발·빌드·테스트하는 도구입니다.", "프로젝트 원본, 시뮬레이터 및 빌드 데이터는 앱 본체와 별도입니다. 필요한 개발 환경인지 먼저 확인하세요.", "https://developer.apple.com/xcode/"),
        "com.google.Chrome": ("Google Chrome · 웹 브라우저", "웹사이트를 열고 웹 앱을 사용하는 브라우저입니다.", "북마크·프로필·로그인 정보의 보관 및 동기화 상태를 확인하세요. 앱 본체 삭제와 사용자 데이터 삭제는 별개입니다.", "https://www.google.com/chrome/"),
        "com.microsoft.VSCode": ("Visual Studio Code · 코드 편집기", "소스 코드를 편집하고 개발 작업을 수행하는 도구입니다.", "프로젝트 원본, 확장 기능과 설정은 별도 위치에 있을 수 있습니다. 관련 폴더를 모두 불필요하다고 판단하지 마세요.", "https://code.visualstudio.com/"),
        "com.docker.docker": ("Docker Desktop · 컨테이너 개발 환경", "컨테이너 기반 앱의 개발·실행 환경입니다.", "제거 과정에서 로컬 컨테이너·이미지·볼륨 데이터가 손실될 수 있습니다. 공식 제거 절차와 데이터 백업 안내를 먼저 확인하세요.", "https://docs.docker.com/desktop/uninstall/")
    ]
    static func explanation(for node: StorageNode, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> ItemExplanation {
        let help = URL(string: "https://support.apple.com/102624")!
        if isSystemManaged(node.path) {
            return ItemExplanation(title: "macOS 관리 영역", purpose: "운영체제, 부팅 또는 가상 메모리에 사용하는 영역입니다. 일반 파일 분석으로 모든 사용량을 설명할 수는 없습니다.", impact: "직접 삭제하지 마세요. VM·swap은 macOS가 관리하며 재시동 후 사용량이 달라질 수 있습니다.", evidence: "내장 경로 설명 · 파일별 삭제 안전성을 판정하지 않음", searchQuery: "macOS system storage Apple support", source: help)
        }
        if node.type == .package, let id = node.bundleID, let entry = appCatalog[id] {
            return ItemExplanation(title: entry.0, purpose: entry.1, impact: entry.2,
                                   evidence: "내장 앱 설명 · 공식 페이지 확인 2026-09-27 · 로컬 Bundle ID 일치 기준이며 서명·소유권 인증은 아님",
                                   searchQuery: "\(id) mac app official", source: URL(string: entry.3))
        }
        let rules: [(String, String, String, String, String)] = [
            ("Library/Developer/Xcode/DerivedData", "Xcode 빌드 작업 데이터", "빌드 중간 결과와 인덱스 등이 쌓이는 위치입니다. 프로젝트가 많으면 커질 수 있습니다.", "정리 후 다시 빌드하거나 인덱싱하는 데 시간이 더 걸릴 수 있습니다. Xcode에서 프로젝트와 설정을 확인하세요.", "Xcode DerivedData build data"),
            ("Library/Developer/CoreSimulator", "시뮬레이터 데이터", "개발용 가상 기기와 그 안의 앱·테스트 데이터가 저장됩니다.", "필요한 가상 기기와 데이터인지 Xcode에서 확인하세요. 폴더 전체를 삭제하지 마세요.", "Xcode manage simulator storage"),
            ("Library/Application Support/MobileSync", "iPhone·iPad 백업", "Mac에 저장한 기기 백업입니다. 여러 기기의 백업이 쌓이면 커질 수 있습니다.", "백업을 없애면 해당 시점으로 복원할 수 없습니다. Finder의 백업 관리에서 확인하세요.", "Apple manage iPhone backups Mac"),
            ("Library/Group Containers", "여러 앱의 공유 데이터", "앱 제품군이 함께 사용하는 데이터가 있을 수 있습니다.", "한 앱의 이름과 비슷해도 단독 소유라고 단정할 수 없습니다. 관련 앱을 모두 확인하세요.", "macOS app group containers shared data"),
            ("Library/Containers", "앱 전용 데이터 영역", "샌드박스 앱의 문서·설정·지원 데이터 등이 들어 있습니다.", "캐시만 있는 폴더가 아닙니다. 삭제하면 앱의 문서나 설정이 사라질 수 있습니다.", "macOS sandbox app containers data"),
            ("Library/Application Support", "앱 지원 데이터", "앱의 데이터베이스, 콘텐츠, 설정 등이 저장됩니다.", "실제 작업 데이터가 포함될 수 있습니다. 소유 앱과 내용을 먼저 확인하세요.", "macOS Application Support folder purpose"),
            ("Library/Caches", "앱 캐시", "다시 사용할 자료를 보관해 앱 작업을 빠르게 하는 영역입니다.", "재생성·재다운로드가 필요할 수 있습니다. 소유 앱의 관리 기능을 먼저 확인하세요.", "macOS app caches storage"),
            ("Library/Messages", "메시지 데이터", "메시지와 첨부 파일이 저장되는 영역입니다.", "메시지 앱에서 검토하세요. 동기화된 삭제가 다른 기기에도 반영될 수 있습니다.", "Apple Messages attachments storage Mac"),
            ("Library/Mail", "메일 데이터", "메일과 첨부 파일의 로컬 데이터가 저장되는 영역입니다.", "Mail 앱에서 계정과 보관 정책을 확인하세요. 내부 파일을 직접 정리하면 데이터에 영향을 줄 수 있습니다.", "Apple Mail storage attachments Mac"),
            ("Library/CloudStorage", "클라우드 동기화 데이터", "클라우드 파일의 로컬 복사본과 온라인 전용 항목이 함께 보일 수 있습니다.", "삭제가 클라우드에도 동기화될 수 있습니다. 공간만 줄이려면 제공 앱의 다운로드 제거 기능을 확인하세요.", "cloud storage remove local download Mac"),
            ("Downloads", "다운로드한 파일", "브라우저 등에서 받은 설치 파일, 압축 파일, 문서 등이 모이는 위치입니다.", "개인 문서도 포함될 수 있습니다. 이름과 내용을 확인한 뒤 Finder에서 정리하세요.", "Apple Mac manage Downloads storage")
        ]
        for (relative, title, purpose, impact, query) in rules where within(node.path, home + "/" + relative) {
            return ItemExplanation(title: title, purpose: purpose, impact: impact,
                                   evidence: "내장 경로 유형 설명 · 2026-09-19 · 이 항목의 내용을 읽은 결과는 아님", searchQuery: query,
                                   source: relative.contains("MobileSync") ? URL(string: "https://support.apple.com/108809") : nil)
        }
        if node.type == .package {
            let query = node.bundleID.flatMap { validBundleID($0) ? "\($0) mac app official" : nil }
            return ItemExplanation(title: node.appName ?? "앱 또는 보관함 묶음", purpose: "여러 내부 파일을 하나로 표시하는 패키지입니다. 앱 이름과 식별자는 로컬 메타데이터에서 읽었습니다. 용도나 개발사 신뢰성은 아직 확인하지 않았습니다.", impact: "앱은 앱 관리에서 검토하세요. 사진 보관함 등은 원본 데이터가 들어 있으므로 내부 파일을 개별 삭제하지 마세요.", evidence: "로컬 패키지 정보 · 온라인 검증 전", searchQuery: query)
        }
        return ItemExplanation(title: "용도를 아직 확인하지 못했습니다", purpose: "이름만으로 소유 앱이나 용도를 추정하지 않습니다. 전체 경로와 상위 폴더를 확인하세요.", impact: "큰 항목이라고 불필요한 것은 아닙니다. Finder에서 내용을 확인하고 필요한 데이터를 보관하세요.", evidence: "용도 미확인 · 개인 파일명과 전체 경로는 웹에 전송하지 않음")
    }
}
