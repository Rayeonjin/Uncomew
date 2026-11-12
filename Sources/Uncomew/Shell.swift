import Foundation
import Darwin

struct ShellResult {
    let output: String
    let error: String
    let status: Int32
}

enum Shell {
    // Each stream is drained independently while the child runs. Waiting for exit
    // before reading can deadlock when either OS pipe buffer fills (notably du stderr).
    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private(set) var truncated = false

        func read(from handle: FileHandle) {
            let maximum = 4 * 1024 * 1024
            while true {
                let chunk = handle.readData(ofLength: 64 * 1024)
                if chunk.isEmpty { break }
                lock.lock()
                let room = max(0, maximum - data.count)
                data.append(chunk.prefix(room))
                if chunk.count > room { truncated = true }
                lock.unlock()
            }
        }

        var string: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 120) -> ShellResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        // Diagnostic parsing must not depend on the user's language settings.
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            let readers = DispatchGroup()
            let out = OutputBuffer()
            let err = OutputBuffer()
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                out.read(from: stdout.fileHandleForReading)
                readers.leave()
            }
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                err.read(from: stderr.fileHandleForReading)
                readers.leave()
            }
            let deadline = Date().addingTimeInterval(timeout)
            var stopped: Date?
            var stopReason = ""
            while process.isRunning {
                let cancelled = withUnsafeCurrentTask { $0?.isCancelled ?? false }
                if stopped == nil && (cancelled || Date() >= deadline) {
                    stopReason = cancelled ? "Command cancelled." : "Command timed out."
                    stopped = Date()
                    process.terminate()
                }
                if let stopped, Date().timeIntervalSince(stopped) > 1, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            process.waitUntilExit()
            readers.wait()
            var diagnostic = err.string
            if !stopReason.isEmpty { diagnostic += "\n" + stopReason }
            if out.truncated || err.truncated { diagnostic += "\nCommand output exceeded the 4 MB per-stream limit." }
            return ShellResult(
                output: out.string,
                error: diagnostic,
                status: process.terminationStatus
            )
        } catch {
            return ShellResult(output: "", error: error.localizedDescription, status: -1)
        }
    }
}
