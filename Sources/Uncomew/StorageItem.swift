import Foundation

struct StorageItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case user = "User"
        case application = "Application"
        case developer = "Developer"
        case system = "System"
        case cache = "Cache"
        case backup = "Backup"
        case other = "Other"
    }

    enum Safety: String {
        case normal = "Review"
        case caution = "Caution"
        case systemManaged = "System Managed"
    }

    let id = UUID()
    let name: String
    let path: String
    let bytes: Int64
    let kind: Kind
    let safety: Safety
    let explanation: String
    let canRevealInFinder: Bool

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct DiskSummary {
    var totalBytes: Int64 = 0
    var availableBytes: Int64 = 0
    // Optional: unsupported/denied estimates must never appear as zero free space.
    var importantAvailableBytes: Int64?
    var finderComparableBytes: Int64? {
        guard let value = importantAvailableBytes, value >= availableBytes, value <= totalBytes else { return nil }
        return value
    }
    var additionalAvailableBytes: Int64? {
        finderComparableBytes.map { $0 - availableBytes }
    }
    var visibleScannedBytes: Int64 = 0
    var systemManagedBytes: Int64 = 0

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
    var hiddenEstimateBytes: Int64 {
        max(0, usedBytes - visibleScannedBytes - systemManagedBytes)
    }
}

// Extension-based hints only: never read file contents to classify a result.
enum BrowseFileKind: String, CaseIterable, Identifiable {
    case all = "모든 종류", video = "동영상", image = "사진·이미지", audio = "음악·오디오"
    case archive = "압축·디스크 이미지", document = "문서", other = "기타 파일"
    var id: String { rawValue }
    static func classify(path: String) -> Self {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ["mp4", "mov", "m4v", "mkv", "avi", "webm", "mpeg", "mpg"].contains(ext) { return .video }
        if ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "webp", "raw", "dng", "svg", "psd"].contains(ext) { return .image }
        if ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "opus"].contains(ext) { return .audio }
        if ["zip", "7z", "rar", "tar", "gz", "bz2", "xz", "dmg", "iso", "pkg"].contains(ext) { return .archive }
        if ["pdf", "txt", "md", "rtf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "csv", "epub"].contains(ext) { return .document }
        return .other
    }
}

enum BrowseMinimumSize: Int64, CaseIterable, Identifiable {
    case all = 0, mb100 = 100_000_000, gb1 = 1_000_000_000, gb10 = 10_000_000_000
    var id: Int64 { rawValue }
    var title: String { self == .all ? "모든 크기" : ByteCountFormatter.string(fromByteCount: rawValue, countStyle: .file) + " 이상" }
}

struct StorageBrowseFilter {
    var kind: BrowseFileKind = .all
    var minimum: BrowseMinimumSize = .all
    var folder: String?
    func matches(_ node: StorageNode) -> Bool {
        if let folder, !node.path.hasPrefix(folder == "/" ? "/" : folder + "/") { return false }
        if kind != .all && (node.type != .file || BrowseFileKind.classify(path: node.path) != kind) { return false }
        if minimum != .all && (node.allocatedBytes == nil || node.allocatedBytes! < minimum.rawValue) { return false }
        return true
    }
}
