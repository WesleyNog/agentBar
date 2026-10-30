import Foundation

/// Uma sessão do Claude Code registrada em `~/.claude/sessions/<pid>.json`.
public struct ClaudeSession: Sendable, Equatable, Identifiable {
    public var id: String { sessionId }
    public let sessionId: String
    public let pid: Int32
    public let cwd: String?
    public let name: String?
    /// Valor cru do Claude Code: `busy`, `idle`, `waiting`…
    public let status: String?
    public let isAlive: Bool

    public init(sessionId: String, pid: Int32, cwd: String?, name: String?, status: String?, isAlive: Bool) {
        self.sessionId = sessionId
        self.pid = pid
        self.cwd = cwd
        self.name = name
        self.status = status
        self.isAlive = isAlive
    }
}

public enum SessionRegistry {
    public typealias Probe = @Sendable (_ pid: Int32, _ startedAt: Date?) -> Bool

    /// Lê todas as sessões registradas. Arquivos ilegíveis são ignorados.
    public static func load(
        from directory: URL,
        probe: Probe = { ProcessProbe.isRunning(pid: $0, startedAt: $1) }
    ) -> [ClaudeSession] {
        FileInfo.contents(of: directory)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return parse(data, probe: probe)
            }
            .sorted { $0.pid < $1.pid }
    }

    static func parse(_ data: Data, probe: Probe) -> ClaudeSession? {
        guard let file = try? JSONDecoder().decode(SessionFile.self, from: data),
              let pid = file.pid, let sessionId = file.sessionId, !sessionId.isEmpty
        else { return nil }

        return ClaudeSession(
            sessionId: sessionId,
            pid: pid,
            cwd: file.cwd,
            name: file.name,
            status: file.status,
            isAlive: probe(pid, file.procStart.flatMap(parseProcStart))
        )
    }

    /// `procStart` vem no formato do `ps -o lstart`, em UTC: `Fri Oct 30 02:10:04 2026`.
    static func parseProcStart(_ text: String) -> Date? {
        let collapsed = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.date(from: collapsed)
    }

    private struct SessionFile: Decodable {
        let pid: Int32?
        let sessionId: String?
        let cwd: String?
        let name: String?
        let status: String?
        let procStart: String?
    }
}
