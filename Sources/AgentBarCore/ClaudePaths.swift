import Foundation

/// Caminhos dos arquivos do Claude Code que o AgentBar lê, e dos poucos que ele escreve.
public struct ClaudePaths: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `CLAUDE_CONFIG_DIR` quando definido; senão `~/.claude`.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> ClaudePaths {
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            let expanded = (custom as NSString).expandingTildeInPath
            return ClaudePaths(root: URL(fileURLWithPath: expanded, isDirectory: true))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ClaudePaths(root: home.appendingPathComponent(".claude", isDirectory: true))
    }

    // MARK: Arquivos do Claude Code

    public var settingsFile: URL { root.appendingPathComponent("settings.json") }
    public var sessionsDirectory: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    public var projectsDirectory: URL { root.appendingPathComponent("projects", isDirectory: true) }

    // MARK: Pasta do AgentBar

    public var agentBarDirectory: URL { root.appendingPathComponent("agentbar", isDirectory: true) }
    public var rateLimitsFile: URL { agentBarDirectory.appendingPathComponent("rate_limits.json") }
    public var statusLineScript: URL { agentBarDirectory.appendingPathComponent("statusline.sh") }
    public var previousStatusLineFile: URL { agentBarDirectory.appendingPathComponent("previous-statusline.json") }
    public var backupsDirectory: URL { agentBarDirectory.appendingPathComponent("backups", isDirectory: true) }
}
