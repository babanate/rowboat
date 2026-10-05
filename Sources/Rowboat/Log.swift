import Foundation
import os

/// Unified logging with public payloads, mirrored to stderr when
/// ROWBOAT_DEBUG is set (useful when running the bare binary from a terminal).
struct RLog {
    let logger: Logger
    let category: String
    static let echo = ProcessInfo.processInfo.environment["ROWBOAT_DEBUG"] != nil

    init(_ category: String) {
        self.category = category
        logger = Logger(subsystem: "rowboat", category: category)
    }

    func info(_ message: String) { logger.notice("\(message, privacy: .public)"); echo("info", message) }
    func warning(_ message: String) { logger.warning("\(message, privacy: .public)"); echo("warn", message) }
    func error(_ message: String) { logger.error("\(message, privacy: .public)"); echo("error", message) }

    private func echo(_ level: String, _ message: String) {
        guard Self.echo else { return }
        FileHandle.standardError.write("[\(category)] \(level): \(message)\n".data(using: .utf8)!)
    }
}

enum Log {
    static let app = RLog("app")
    static let ax = RLog("ax")
    static let input = RLog("input")
    static let mode = RLog("mode")
}
