import Foundation

// Standalone runner intentionally uses only Foundation: no Xcode/XCTest runtime required.
@main
struct MeasurementTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        let home = "/Users/test"
        func parse(_ output: String, _ error: String = "", _ status: Int32 = 0,
                   path: String = "/Library") -> DirectoryMeasurement {
            DirectoryMeasurement.parse(ShellResult(output: output, error: error, status: status), path: path, home: home)
        }
        let partial = parse("42\t/Library\n", "du: /Library/Protected: Operation not permitted\n", 1)
        check(partial.bytes == 42 * 1024, "Preserve valid partial total")
        check(partial.warnings.first?.kind == .protectedSystemArea, "System protection is not missing FDA")
        check(partial.warnings.first?.isPartial == true, "Partial measurement disclosed")
        for root in ["/private", "/System/Volumes/Preboot"] {
            let result = parse("7\t\(root)\n", "du: \(root)/protected: Permission denied\n", 1, path: root)
            check(result.bytes == 7168 && result.warnings.first?.kind == .protectedSystemArea, "Protected root classified")
        }
        let privacy = parse("1\t\(home)\n", "du: \(home)/Library/Mail/V10: Operation not permitted\n", 1, path: home)
        check(privacy.warnings.first?.kind == .fullDiskAccessMayBeRequired, "Privacy evidence offers qualified FDA guidance")
        let ordinary = parse("", "du: \(home)/Work: Permission denied\n", 1, path: home)
        check(ordinary.bytes == nil && ordinary.warnings.first?.kind == .permissionDenied, "Ordinary permissions do not imply FDA")
        let lookalike = parse("", "du: \(home)/Library/MailArchive: Permission denied\n", 1, path: home)
        check(lookalike.warnings.first?.kind == .permissionDenied, "Privacy path boundaries respected")
        let missing = parse("", "du: /Library/gone: No such file or directory\n", 1)
        check(missing.bytes == nil && missing.warnings.first?.kind == .unavailable, "Missing is not zero or FDA")
        let io = parse("2\t/Library\n", "du: /Library/disk: Input/output error\n", 1)
        check(io.bytes == 2048 && io.warnings.first?.kind == .filesystem, "I/O error preserves partial result")
        check(parse("0\t/Library\n").bytes == 0, "Real zero remains valid")
        for value in ["-1", "9223372036854775807", "nonsense"] {
            check(parse("\(value)\t/Library\n").bytes == nil, "Reject invalid/overflowing totals")
        }
        check(parse("10\t/other\n").bytes == nil, "Reject unrelated output")
        check(parse("", "", 1).warnings.first?.kind == .filesystem, "Exit status alone does not imply FDA")
        check(parse("", "", 0).warnings.count == 1, "Missing output is disclosed even on status zero")
        check(parse("", "du: invalid option", 1).warnings.first?.kind == .filesystem, "Unstructured diagnostics do not crash")
        let unusual = "/tmp/한글 space\tand\nnewline"
        check(parse("3\t\(unusual)\n", path: unusual).bytes == 3072, "Preserve entire filename")

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Uncomew-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("한글 space")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 65, count: 1024 * 1024).write(to: folder.appendingPathComponent("data file"))
        let measured = DirectoryMeasurement.measure(folder.path)
        check((measured.bytes ?? 0) > 0 && measured.warnings.isEmpty, "Real Unicode/spaces directory scan finishes")
        let absent = DirectoryMeasurement.measure(root.appendingPathComponent("missing").path)
        check(absent.bytes == nil && absent.warnings.first?.kind == .unavailable, "Real missing path")
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: folder)
        let linkSize = DirectoryMeasurement.measure(link.path)
        check((linkSize.bytes ?? Int64.max) < (measured.bytes ?? 0), "du must not follow symlink target")

        let protected = root.appendingPathComponent("protected")
        try fm.createDirectory(at: protected, withIntermediateDirectories: true)
        try Data([1]).write(to: protected.appendingPathComponent("private file"))
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: protected.path)
        let denied = DirectoryMeasurement.measure(root.path)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: protected.path)
        check(denied.bytes != nil && denied.warnings.contains(where: { $0.kind == .permissionDenied }),
              "Real inaccessible descendant retains partial total without FDA advice")

        // More than pipe capacity on both channels used to deadlock Shell.run.
        let flood = Shell.run("/usr/bin/awk", ["BEGIN { for(i=0;i<20000;i++) { print \"stdout payload 01234567890123456789\"; print \"stderr payload 01234567890123456789\" > \"/dev/stderr\" } }"])
        check(flood.status == 0, "Flood process finishes")
        check(flood.output.utf8.count > 600000 && flood.error.utf8.count > 600000, "Both streams drained completely")
        let launchError = Shell.run("/nonexistent/uncomew-test", [])
        check(launchError.status == -1 && !launchError.error.isEmpty, "Launch errors preserved")
        let timed = Shell.run("/bin/sleep", ["5"], timeout: 0.1)
        check(timed.error.contains("timed out"), "Hung command terminates with timeout diagnostic")
        let overflow = Shell.run("/usr/bin/awk", ["BEGIN { for(i=0;i<300000;i++) print \"012345678901234567890123456789\" }"])
        check(overflow.output.utf8.count == 4 * 1024 * 1024 && overflow.error.contains("limit"), "Large output is bounded and disclosed")
        print("Passed \(checks) measurement/process regression checks.")
    }
}
