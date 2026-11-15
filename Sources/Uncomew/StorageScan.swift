import Foundation
import Darwin

struct StorageNode: Identifiable, Hashable, Sendable {
    enum EntryType: String, Sendable { case folder, package, file, symbolicLink, other }
    enum Measurement: String, Sendable { case scanning, complete, partial, unavailable, excluded }
    var id: String { path }
    let path: String
    let parent: String?
    let type: EntryType
    let insidePackage: Bool
    var fileIdentity: String?
    var modifiedAt: Date?
    var linkCount: UInt32 = 1
    var children: [String] = []
    var allocatedBytes: Int64?
    var logicalBytes: Int64?
    var measurement: Measurement = .scanning
    var permissionDenied = false
    var note: String?
    var bundleID: String?
    var appName: String?
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var isFolder: Bool { type == .folder || type == .package }
    var sizeText: String {
        guard let allocatedBytes else { return measurement == .scanning ? "확인 중" : "확인 불가" }
        let size = ByteCountFormatter.string(fromByteCount: allocatedBytes, countStyle: .file)
        return measurement == .complete ? size : "\(size) · 일부"
    }
}

struct ScanBatch: Sendable {
    let nodes: [StorageNode]
    let currentPath: String
    let visited: Int
}

// Metadata-only traversal. Never opens file contents or follows symbolic links.
// A single index serves all three views; view changes do not launch another scan.
enum StorageScan {
    static func run(roots: [String], limit: Int = 250_000,
                    publish: @escaping @Sendable (ScanBatch) async -> Void) async throws {
        let worker = Worker(limit: limit, publish: publish)
        let scanRoots = normalizedRoots(roots)
        for (index, root) in scanRoots.enumerated() {
            try Task.checkCancellation()
            guard worker.count < worker.limit else { break }
            // Reserve a fair share for later roots, rather than starving them behind a huge Home.
            worker.ceiling = worker.count + max(1, (worker.limit - worker.count) / (scanRoots.count - index))
            var info = stat()
            let device = lstat(root, &info) == 0 ? info.st_dev : 0
            _ = try await worker.visit(root, parent: nil, insidePackage: false, device: device, depth: 0)
        }
        await worker.flush(force: true)
    }

    static func normalizedRoots(_ paths: [String]) -> [String] {
        var unique: [String] = []
        for raw in paths {
            let path = URL(fileURLWithPath: raw).standardizedFileURL.path
            if !unique.contains(path) { unique.append(path) }
        }
        return unique.filter { path in
            !unique.contains { root in
                root != path && path.hasPrefix(root == "/" ? "/" : root + "/")
            }
        }
    }

    private final class Worker {
        let limit: Int
        var ceiling: Int
        let publish: @Sendable (ScanBatch) async -> Void
        var pending: [String: StorageNode] = [:]
        var count = 0
        var lastPublish = Date.distantPast
        var current = ""
        var seenFiles = Set<String>()

        init(limit: Int, publish: @escaping @Sendable (ScanBatch) async -> Void) {
            self.limit = max(1, limit)
            self.ceiling = max(1, limit)
            self.publish = publish
        }

        func flush(force: Bool = false) async {
            guard !pending.isEmpty, force || Date().timeIntervalSince(lastPublish) >= 0.6 else { return }
            let batch = ScanBatch(nodes: Array(pending.values), currentPath: current, visited: count)
            pending.removeAll(keepingCapacity: true)
            lastPublish = Date()
            await publish(batch)
        }

        func visit(_ path: String, parent: String?, insidePackage: Bool,
                   device: dev_t, depth: Int) async throws -> (allocated: Int64, logical: Int64, complete: Bool) {
            try Task.checkCancellation()
            current = path
            count += 1
            var metadata = stat()
            guard lstat(path, &metadata) == 0 else {
                let code = errno
                var node = StorageNode(path: path, parent: parent, type: .other, insidePackage: insidePackage)
                node.measurement = .unavailable
                node.note = "\(String(cString: strerror(code))) (\(code)). 이 항목은 용량에 포함되지 않았습니다."
                if code == EACCES || code == EPERM { node.permissionDenied = true; node.note! += " 접근 권한 또는 macOS 보호로 읽을 수 없습니다." }
                pending[path] = node
                await flush()
                return (0, 0, false)
            }
            let mode = metadata.st_mode & mode_t(S_IFMT)
            let directory = mode == mode_t(S_IFDIR)
            let url = URL(fileURLWithPath: path)
            let package = directory && ((try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
                || ["app", "photoslibrary", "photolibrary", "bundle"].contains(url.pathExtension.lowercased()))
            let type: StorageNode.EntryType = directory ? (package ? .package : .folder)
                : (mode == mode_t(S_IFLNK) ? .symbolicLink : (mode == mode_t(S_IFREG) ? .file : .other))
            var node = StorageNode(path: path, parent: parent, type: type, insidePackage: insidePackage)
            node.fileIdentity = "\(metadata.st_dev):\(metadata.st_ino):\(metadata.st_birthtimespec.tv_sec):\(metadata.st_birthtimespec.tv_nsec):\(metadata.st_ctimespec.tv_sec):\(metadata.st_ctimespec.tv_nsec)"
            node.modifiedAt = Date(timeIntervalSince1970: Double(metadata.st_mtimespec.tv_sec))
            node.linkCount = directory ? 1 : UInt32(metadata.st_nlink)
            if package && url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url) {
                node.bundleID = bundle.bundleIdentifier
                node.appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            }
            var allocated = max(0, Int64(metadata.st_blocks)) * 512
            var logical = directory ? 0 : max(0, Int64(metadata.st_size))
            // Show each hard-link entry, but count its storage only once in ancestor totals.
            let identity = "\(metadata.st_dev):\(metadata.st_ino)"
            let duplicate = !directory && metadata.st_nlink > 1 && !seenFiles.insert(identity).inserted
            if duplicate { node.note = "같은 파일을 가리키는 하드 링크입니다. 상위 폴더 합계에는 한 번만 포함합니다." }
            if type == .symbolicLink { node.note = "다른 위치를 가리키는 링크입니다. 연결된 대상은 따라가서 분석하지 않았습니다." }
            if directory && metadata.st_dev != device {
                node.measurement = .excluded
                node.note = "다른 볼륨의 내용은 제외했습니다. 이 위치를 별도 폴더로 선택해 분석할 수 있습니다."
                pending[path] = node
                return (0, 0, false)
            }
            if directory {
                node.allocatedBytes = allocated
                node.logicalBytes = logical
                pending[path] = node
                await flush()
                var complete = true
                do {
                    let children = try DirectoryListing.read(path).sorted()
                    node.children = children.prefix(max(0, ceiling - count)).map { url.appendingPathComponent($0).path }
                    var completedChildren = 0
                    for childPath in node.children {
                        try Task.checkCancellation()
                        guard count < ceiling, depth < 256 else {
                            complete = false
                            node.note = "분석 한도에 도달했습니다. 더 작은 폴더를 선택해 분석하세요."
                            break
                        }
                        pending[path] = node
                        let result = try await visit(childPath, parent: path, insidePackage: insidePackage || package,
                                                     device: device, depth: depth + 1)
                        completedChildren += 1
                        allocated += result.allocated
                        logical += result.logical
                        complete = complete && result.complete
                        node.allocatedBytes = allocated
                        node.logicalBytes = logical
                        pending[path] = node
                    }
                    if completedChildren < children.count {
                        complete = false
                        node.children = Array(node.children.prefix(completedChildren))
                        node.note = "분석 한도에 도달했습니다. 더 작은 폴더를 선택해 분석하세요."
                    }
                } catch is CancellationError {
                    node.measurement = .partial
                    node.note = "분석이 중지되었습니다. 현재까지 확인한 용량입니다."
                    pending[path] = node
                    await flush(force: true)
                    throw CancellationError()
                } catch {
                    complete = false
                    let failure = error as NSError
                    node.permissionDenied = (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError) || (failure.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(failure.code))
                    node.note = "폴더 내용을 읽지 못했습니다: \(error.localizedDescription)"
                    // A directory's own metadata does not measure its inaccessible contents.
                    node.allocatedBytes = nil
                    node.logicalBytes = nil
                    node.measurement = .unavailable
                    pending[path] = node
                    await flush()
                    return (0, 0, false)
                }
                node.measurement = complete ? .complete : .partial
            } else { node.measurement = .complete }
            node.allocatedBytes = allocated
            node.logicalBytes = logical
            pending[path] = node
            await flush()
            return (duplicate ? 0 : allocated, duplicate ? 0 : logical, node.measurement == .complete)
        }
    }
}
