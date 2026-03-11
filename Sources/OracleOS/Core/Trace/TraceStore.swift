import Foundation

public final class TraceStore: @unchecked Sendable {
    public let directoryURL: URL

    private let encoder: JSONEncoder

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    public convenience init() {
        self.init(directoryURL: Self.resolveSessionsDirectory())
    }

    @discardableResult
    public func append(_ event: TraceEvent) throws -> URL {
        let fileURL = directoryURL.appendingPathComponent("\(event.sessionID).jsonl")
        let data = try encoder.encode(event)
        var line = data
        line.append(0x0A)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        return fileURL
    }

    public static func traceRootDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["GHOST_OS_TRACE_DIR"], !override.isEmpty {
            return URL(
                fileURLWithPath: NSString(string: override).expandingTildeInPath,
                isDirectory: true
            )
        }

        let currentDirectory = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: currentDirectory, isDirectory: true)
            .appendingPathComponent(".traces", isDirectory: true)
    }

    public static func resolveSessionsDirectory() -> URL {
        traceRootDirectory().appendingPathComponent("sessions", isDirectory: true)
    }
}
