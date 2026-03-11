import Foundation

public final class TraceStore: @unchecked Sendable {
    public let sessionID: String
    public let baseDirectory: URL
    public let traceFileURL: URL

    public init(sessionID: String = UUID().uuidString, baseDirectory: URL? = nil) {
        self.sessionID = sessionID
        self.baseDirectory = Self.resolveBaseDirectory(explicit: baseDirectory)
        self.traceFileURL = self.baseDirectory.appendingPathComponent("\(sessionID).jsonl")
        try? FileManager.default.createDirectory(
            at: self.baseDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    @discardableResult
    public func append(_ event: TraceEvent) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        var line = data
        line.append(0x0A)

        if !FileManager.default.fileExists(atPath: traceFileURL.path) {
            FileManager.default.createFile(atPath: traceFileURL.path, contents: nil, attributes: nil)
        }

        let handle = try FileHandle(forWritingTo: traceFileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        return traceFileURL
    }

    public func artifactsDirectory() -> URL {
        let directory = baseDirectory.appendingPathComponent("artifacts").appendingPathComponent(sessionID)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }

    private static func resolveBaseDirectory(explicit: URL?) -> URL {
        if let explicit {
            return explicit
        }
        if let override = ProcessInfo.processInfo.environment["GHOST_OS_TRACE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        }
        let path = NSString(string: "~/.ghost-os/logs/traces").expandingTildeInPath
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
