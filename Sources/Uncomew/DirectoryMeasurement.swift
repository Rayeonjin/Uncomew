import Foundation

struct ScanWarning: Hashable {
    enum Kind: String {
        case fullDiskAccessMayBeRequired
        case protectedSystemArea
        case permissionDenied
        case unavailable
        case filesystem
    }

    let path: String
    let kind: Kind
    let detail: String
    let isPartial: Bool

    var message: String {
        let scope = isPartial
            ? "The displayed size for \(path) may be incomplete."
            : "Could not measure \(path)."
        let explanation: String
        switch kind {
        case .fullDiskAccessMayBeRequired:
            explanation = "Access to privacy-protected user data was denied. Full Disk Access may help; this does not prove it is disabled."
        case .protectedSystemArea:
            explanation = "macOS protects some system locations even with Full Disk Access."
        case .permissionDenied:
            explanation = "Access was denied. File permissions or macOS protections may be responsible."
        case .unavailable:
            explanation = "A path was missing or unavailable during the scan."
        case .filesystem:
            explanation = "A filesystem or measurement error occurred."
        }
        return "\(scope) \(explanation)\n\(detail)"
    }
}

struct DirectoryMeasurement {
    let bytes: Int64?
    let warnings: [ScanWarning]

    static func measure(_ path: String) -> Self {
        // fileExists cannot distinguish inaccessible paths from absent ones.
        parse(Shell.run("/usr/bin/du", ["-skx", path]), path: path)
    }

    static func parse(_ result: ShellResult, path: String,
                      home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> Self {
        // Match the complete summary record; filenames may contain spaces, tabs,
        // or newlines. Never interpret a descendant's output as the requested total.
        let suffix = "\t\(path)\n"
        var bytes: Int64?
        if result.output.hasSuffix(suffix) {
            let number = result.output.dropLast(suffix.count)
            if let kib = Int64(number), kib >= 0 {
                let product = kib.multipliedReportingOverflow(by: 1024)
                if !product.overflow { bytes = product.partialValue }
            }
        }

        let lines = result.error.split(separator: "\n").map(String.init)
        var warnings = lines.map { line -> ScanWarning in
            let denied = line.hasSuffix(": Operation not permitted") || line.hasSuffix(": Permission denied")
            let failedPath: String
            if line.hasPrefix("du: "), let end = line.range(of: ": ", options: .backwards),
               end.lowerBound >= line.index(line.startIndex, offsetBy: 4) {
                failedPath = String(line[line.index(line.startIndex, offsetBy: 4)..<end.lowerBound])
            } else {
                failedPath = path
            }
            let privacyRoots = ["\(home)/Library/Mail", "\(home)/Library/Messages", "\(home)/Library/Safari",
                                "\(home)/Library/Application Support/MobileSync"]
            let systemRoots = ["/Library", "/private", "/System"]
            let kind: ScanWarning.Kind
            if denied && privacyRoots.contains(where: { contains(failedPath, in: $0) }) {
                kind = .fullDiskAccessMayBeRequired
            } else if denied && systemRoots.contains(where: { contains(failedPath, in: $0) }) {
                kind = .protectedSystemArea
            } else if denied {
                kind = .permissionDenied
            } else if line.hasSuffix(": No such file or directory") || line.hasSuffix(": Not a directory") {
                kind = .unavailable
            } else {
                kind = .filesystem
            }
            return ScanWarning(path: path, kind: kind, detail: line, isPartial: bytes != nil)
        }
        if warnings.isEmpty && (result.status != 0 || bytes == nil) {
            warnings.append(ScanWarning(path: path, kind: .filesystem,
                                        detail: "du exited with status \(result.status)\(bytes == nil ? " without a valid size" : "").",
                                        isPartial: bytes != nil))
        }
        return Self(bytes: bytes, warnings: warnings)
    }

    private static func contains(_ path: String, in root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}
