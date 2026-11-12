import Foundation
import Darwin

struct FileIdentity: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    static func read(_ path: String) -> Self? {
        var value = stat()
        guard lstat(path, &value) == 0, value.st_mode & mode_t(S_IFMT) != mode_t(S_IFLNK) else { return nil }
        return Self(device: value.st_dev, inode: UInt64(value.st_ino))
    }
}

struct RemovalCandidate: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let identity: FileIdentity
    let allowedParent: String
    let bytes: Int64
    let isApplication: Bool
}

enum RemovalSafety {
    static func approvedInstalledApp(_ path: String, home: String) -> Bool {
        guard URL(fileURLWithPath: path).standardizedFileURL.path == path,
              URL(fileURLWithPath: path).pathExtension.lowercased() == "app" else { return false }
        for root in ["/Applications", home + "/Applications"] where path.hasPrefix(root + "/") {
            let parts = path.dropFirst(root.count + 1).split(separator: "/", omittingEmptySubsequences: false)
            if (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) { return true }
        }
        return false
    }
    static func noSymlinkAncestors(_ path: String) -> Bool {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        while url.path != "/" {
            var value = stat()
            guard lstat(url.path, &value) == 0, value.st_mode & mode_t(S_IFMT) != mode_t(S_IFLNK) else { return false }
            url.deleteLastPathComponent()
        }
        return true
    }
    static func capture(path: String, allowedParent: String, bytes: Int64, isApplication: Bool = false) -> RemovalCandidate? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path == path, url.deletingLastPathComponent().path == allowedParent,
              path != "/", !ItemKnowledge.isSystemManaged(path), noSymlinkAncestors(path),
              let identity = FileIdentity.read(path) else { return nil }
        if isApplication {
            guard url.pathExtension.lowercased() == "app", Bundle(url: url) != nil else { return nil }
        }
        return RemovalCandidate(path: path, identity: identity, allowedParent: allowedParent, bytes: bytes, isApplication: isApplication)
    }
    static func isStillValid(_ candidate: RemovalCandidate) -> Bool {
        guard let current = capture(path: candidate.path, allowedParent: candidate.allowedParent,
                                    bytes: candidate.bytes, isApplication: candidate.isApplication) else { return false }
        return current.identity == candidate.identity
    }
    static func relatedPaths(bundleID: String, home: String) -> [(path: String, parent: String)] {
        guard ItemKnowledge.validBundleID(bundleID) else { return [] }
        let entries = [
            ("Preferences", "\(bundleID).plist"), ("Caches", bundleID),
            ("Application Support", bundleID), ("Containers", bundleID),
            ("Saved Application State", "\(bundleID).savedState"),
            ("HTTPStorages", bundleID), ("WebKit", bundleID), ("Logs", bundleID)
        ]
        return entries.map { directory, name in
            let parent = home + "/Library/" + directory
            return (parent + "/" + name, parent)
        }
    }
}
