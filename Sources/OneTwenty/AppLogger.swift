import Foundation
import OSLog

/// Lightweight dual-sink logger:
/// - Console.app via unified logging (OSLog)
/// - Local file at ~/Library/Logs/OneTwenty/onetwenty.log
///
/// File logging is best-effort and never fatal. If writes fail (for example in
/// restricted environments), the app continues with OSLog only.
final class AppLogger {
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"

        var osLogType: OSLogType {
            switch self {
            case .debug:
                return .debug
            case .info:
                return .info
            case .warning:
                return .default
            case .error:
                return .error
            }
        }
    }

    static let shared = AppLogger()
    private static let debugEnabledDefaultsKey = "OneTwenty.DebugLoggingEnabled"

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let stateLock = NSLock()
    private let queue = DispatchQueue(label: "OneTwenty.AppLogger", qos: .utility)
    private let logger: Logger
    private let formatter = ISO8601DateFormatter()
    private let logURL: URL
    private let backupURL: URL
    private let maxFileSizeBytes: UInt64 = 512 * 1024
    private var debugEnabled: Bool

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        debugEnabledByDefault: Bool = false,
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.example.onetwenty",
        category: String = "app"
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.logger = Logger(subsystem: subsystem, category: category)
        if defaults.object(forKey: Self.debugEnabledDefaultsKey) == nil {
            defaults.set(debugEnabledByDefault, forKey: Self.debugEnabledDefaultsKey)
        }
        self.debugEnabled = defaults.bool(forKey: Self.debugEnabledDefaultsKey)

        let logsDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("OneTwenty")
        self.logURL = logsDir.appendingPathComponent("onetwenty.log")
        self.backupURL = logsDir.appendingPathComponent("onetwenty.log.1")

        do {
            try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        } catch {
            Self.writeToStderr("Failed to create log directory: \(error.localizedDescription)")
        }
    }

    var isDebugEnabled: Bool {
        stateLock.lock()
        let value = debugEnabled
        stateLock.unlock()
        return value
    }

    func setDebugEnabled(_ enabled: Bool) {
        stateLock.lock()
        let changed = debugEnabled != enabled
        debugEnabled = enabled
        stateLock.unlock()

        defaults.set(enabled, forKey: Self.debugEnabledDefaultsKey)
        guard changed else { return }
        info("Debug logging \(enabled ? "enabled" : "disabled").")
    }

    func debug(_ message: String) {
        log(.debug, message)
    }

    func info(_ message: String) {
        log(.info, message)
    }

    func warning(_ message: String) {
        log(.warning, message)
    }

    func error(_ message: String) {
        log(.error, message)
    }

    private func log(_ level: Level, _ message: String) {
        guard shouldLog(level) else { return }

        logger.log(level: level.osLogType, "\(message, privacy: .public)")

        queue.async { [weak self] in
            guard let self else { return }
            self.appendFileLine(level: level, message: message, at: Date())
        }
    }

    private func shouldLog(_ level: Level) -> Bool {
        if level != .debug {
            return true
        }
        return isDebugEnabled
    }

    private func appendFileLine(level: Level, message: String, at timestamp: Date) {
        let line = "[\(formatter.string(from: timestamp))] [\(level.rawValue)] \(message)\n"
        let data = Data(line.utf8)

        rotateIfNeeded(incomingBytes: UInt64(data.count))

        if !fileManager.fileExists(atPath: logURL.path) {
            _ = fileManager.createFile(atPath: logURL.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            Self.writeToStderr("Failed to append log file: \(error.localizedDescription)")
        }
    }

    private func rotateIfNeeded(incomingBytes: UInt64) {
        guard
            let attrs = try? fileManager.attributesOfItem(atPath: logURL.path),
            let currentSize = attrs[.size] as? NSNumber
        else {
            return
        }

        guard currentSize.uint64Value + incomingBytes > maxFileSizeBytes else { return }

        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            if fileManager.fileExists(atPath: logURL.path) {
                try fileManager.moveItem(at: logURL, to: backupURL)
            }
        } catch {
            Self.writeToStderr("Failed to rotate logs: \(error.localizedDescription)")
        }
    }

    private static func writeToStderr(_ text: String) {
        let data = Data(("[OneTwenty] " + text + "\n").utf8)
        try? FileHandle.standardError.write(contentsOf: data)
    }
}
