import Foundation

/// Manages a per-user LaunchAgent to run the app at login.
///
/// Implementation details:
/// - Writes a plist to ~/Library/LaunchAgents/<bundle-id>.agent.plist
/// - Uses `launchctl bootstrap/bootout gui/<uid>` to start/stop the agent
/// - The ProgramArguments points at the app's executable; for SwiftPM runs,
///   we fall back to argv[0] so developers can test without bundling.
enum LoginItemManager {
    private static var agentPlistURL: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.dummy.OneTwenty"
        let fileName = bundleID + ".agent.plist"
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
        return dir.appendingPathComponent(fileName)
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try enable()
        } else {
            try disable()
        }
    }

    private static func enable() throws {
        let fm = FileManager.default
        let url = agentPlistURL
        try fm.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let execPath: String = {
            if let p = Bundle.main.executableURL?.path {
                return p
            }
            // Fallback to argv[0]
            return CommandLine.arguments.first ?? "/usr/bin/true"
        }()

        let plist: [String: Any] = [
            "Label": url.deletingPathExtension().lastPathComponent,
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProgramArguments": [execPath],
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)

        // Bootstrap the agent
        try runLaunchctl(["bootstrap", "gui/\(uid())", url.path])
    }

    private static func disable() throws {
        let url = agentPlistURL
        if FileManager.default.fileExists(atPath: url.path) {
            // Stop the agent
            do {
                try runLaunchctl(["bootout", "gui/\(uid())", url.path])
            } catch {
                // launchctl returns non-zero if the job is already unloaded;
                // in that case, continue removing the plist.
                let message = error.localizedDescription.lowercased()
                let isAlreadyStopped = message.contains("no such process")
                    || message.contains("service could not be found")
                if !isAlreadyStopped {
                    throw error
                }
            }
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func runLaunchctl(_ args: [String]) throws {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        guard proc.terminationStatus == 0 else {
            let details = output.isEmpty ? "" : ": \(output)"
            throw NSError(
                domain: "LoginItemManager", code: Int(proc.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "launchctl failed with code \(proc.terminationStatus)\(details)"
                ])
        }
    }

    /// Current user's numeric UID (used in launchctl's `gui/<uid>` target).
    private static func uid() -> Int {
        return Int(getuid())
    }
}
