import Foundation

// Some filesystem providers / privacy requests can stall inside open(). Bound the
// caller's wait and the number of outstanding OS reads; late replies are discarded.
enum DirectoryListing {
    private static let slots = DispatchSemaphore(value: 4)
    private final class Reply: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<[String], Error>?
        func set(_ value: Result<[String], Error>) { lock.lock(); result = value; lock.unlock() }
        func get() -> Result<[String], Error>? { lock.lock(); defer { lock.unlock() }; return result }
    }
    static func read(_ path: String, timeout: TimeInterval = 5,
                     loader: (@Sendable () throws -> [String])? = nil) throws -> [String] {
        try Task.checkCancellation()
        guard slots.wait(timeout: .now()) == .success else {
            throw NSError(domain: "Uncomew.DirectoryListing", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "다른 위치의 파일 시스템 응답이 지연되어 이 위치를 건너뛰었습니다. 잠시 후 이 폴더만 다시 분석하세요."])
        }
        let reply = Reply(), done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            defer { slots.signal(); done.signal() }
            reply.set(Result { try loader?() ?? FileManager.default.contentsOfDirectory(atPath: path) })
        }
        let deadline = Date().addingTimeInterval(timeout)
        while done.wait(timeout: .now() + 0.05) != .success {
            try Task.checkCancellation()
            if Date() >= deadline {
                throw NSError(domain: "Uncomew.DirectoryListing", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "폴더 응답이 5초 이상 지연되어 건너뛰었습니다. 접근 요청이나 연결 상태를 확인한 뒤 이 폴더만 다시 분석하세요."])
            }
        }
        try Task.checkCancellation()
        return try reply.get()!.get()
    }
}
