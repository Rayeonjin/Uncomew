import Foundation
import Darwin

struct TrashReceipt: Identifiable, Sendable {
    let id = UUID()
    let originalPath: String
    let trashedPath: String
    let identity: FileIdentity
    let parentIdentity: FileIdentity
}

enum TrashService {
    enum Failure: LocalizedError {
        case changed, occupied, parentChanged
        var errorDescription: String? {
            switch self {
            case .changed: return "항목이 바뀌었거나 없어졌습니다. 경로를 다시 확인하세요."
            case .occupied: return "원래 위치에 다른 항목이 있습니다. 덮어쓰지 않았습니다."
            case .parentChanged: return "원래 상위 폴더가 바뀌었거나 접근할 수 없습니다. Finder에서 복원 위치를 확인하세요."
            }
        }
    }
    // Foundation's Trash operation is recoverable, but validation + move is not atomic.
    static func move(_ candidate: RemovalCandidate) throws -> TrashReceipt? {
        guard RemovalSafety.isStillValid(candidate), let parent = FileIdentity.read(candidate.allowedParent) else { throw Failure.changed }
        var destination: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: candidate.path), resultingItemURL: &destination)
        guard let path = destination?.path, RemovalSafety.noSymlinkAncestors(path),
              FileIdentity.read(path) == candidate.identity else { return nil }
        return TrashReceipt(originalPath: candidate.path, trashedPath: path, identity: candidate.identity, parentIdentity: parent)
    }
    static func restore(_ receipt: TrashReceipt) throws {
        let original = URL(fileURLWithPath: receipt.originalPath)
        let parent = original.deletingLastPathComponent().path
        guard RemovalSafety.noSymlinkAncestors(parent), FileIdentity.read(parent) == receipt.parentIdentity else { throw Failure.parentChanged }
        guard RemovalSafety.noSymlinkAncestors(receipt.trashedPath), FileIdentity.read(receipt.trashedPath) == receipt.identity else { throw Failure.changed }
        var entry = stat()
        guard lstat(receipt.originalPath, &entry) != 0 && errno == ENOENT else { throw Failure.occupied }
        // moveItem fails if a destination appears meanwhile; never replace or remove it.
        try FileManager.default.moveItem(at: URL(fileURLWithPath: receipt.trashedPath), to: original)
    }
}
