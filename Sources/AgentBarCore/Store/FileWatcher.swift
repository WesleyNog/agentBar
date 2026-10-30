import CoreServices
import Foundation

/// Observa uma pasta (recursivamente, via FSEvents) e avisa quando muda algo que interessa ao AgentBar.
public final class FileWatcher: @unchecked Sendable {
    private let root: String
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "AgentBar.FileWatcher")
    private var stream: FSEventStreamRef?

    /// `nil` se o FSEvents não aceitar a pasta. Quem usa deve ter um timer de reserva.
    public init?(root: URL, latency: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) {
        self.root = ChangeFilter.canonicalPath(root)
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.handle(paths.prefix(count))
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [self.root] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func handle(_ paths: some Sequence<String>) {
        if paths.contains(where: { ChangeFilter.isRelevant(path: $0, root: root) }) {
            onChange()
        }
    }
}

/// Decide quais mudanças em `~/.claude` pedem uma nova leitura.
public enum ChangeFilter {
    public static func isRelevant(path: String, root: String) -> Bool {
        guard path.hasPrefix(root + "/") else { return false }
        let relative = path.dropFirst(root.count + 1)
        if relative == "settings.json" { return true }
        if relative.hasPrefix("agentbar/") || relative.hasPrefix("sessions/") { return true }
        // Em `projects`, só as pastas de workflow. Os transcripts da conversa principal mudam o tempo todo.
        return relative.hasPrefix("projects/")
            && (relative.contains("/subagents/workflows/") || relative.contains("/workflows/"))
    }

    /// Caminho real (sem links), como o FSEvents informa: `/var/...` vira `/private/var/...`.
    static func canonicalPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
