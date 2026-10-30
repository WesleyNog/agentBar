import Foundation
import Observation

/// Tudo o que o AgentBar lê do disco num dado momento.
public struct AgentBarSnapshot: Sendable, Equatable {
    public var rateLimits: RateLimitsSnapshot?
    /// `nil` quando o `settings.json` existe mas não é JSON válido.
    public var statusLine: StatusLineInstaller.State?
    public var sessions: [ClaudeSession]
    public var workflows: [WorkflowRun]

    public init(
        rateLimits: RateLimitsSnapshot? = nil,
        statusLine: StatusLineInstaller.State? = .notConfigured,
        sessions: [ClaudeSession] = [],
        workflows: [WorkflowRun] = []
    ) {
        self.rateLimits = rateLimits
        self.statusLine = statusLine
        self.sessions = sessions
        self.workflows = workflows
    }
}

/// Faz as leituras fora da main thread. O scanner guarda cache entre leituras.
actor SnapshotReader {
    private let paths: ClaudePaths
    private let scanner: WorkflowScanner

    init(paths: ClaudePaths) {
        self.paths = paths
        scanner = WorkflowScanner(paths: paths)
    }

    func read(now: Date) -> AgentBarSnapshot {
        let sessions = SessionRegistry.load(from: paths.sessionsDirectory)
        return AgentBarSnapshot(
            rateLimits: RateLimitsReader.read(at: paths.rateLimitsFile),
            statusLine: try? StatusLineInstaller(paths: paths).state(),
            sessions: sessions,
            workflows: scanner.scan(sessions: sessions, now: now)
        )
    }
}

/// Estado do app, sempre em dia com o disco: relê quando os arquivos mudam
/// (no máximo uma vez por `minimumInterval`) e a cada `fallbackInterval` como reserva.
@MainActor
@Observable
public final class AgentBarStore {
    public private(set) var paths: ClaudePaths
    public private(set) var snapshot = AgentBarSnapshot()
    public private(set) var lastRefresh: Date?

    @ObservationIgnored private var reader: SnapshotReader
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var fallbackTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var lastRefreshStart: Date?
    @ObservationIgnored private let minimumInterval: TimeInterval
    @ObservationIgnored private let fallbackInterval: TimeInterval

    public init(paths: ClaudePaths, minimumInterval: TimeInterval = 1, fallbackInterval: TimeInterval = 5) {
        self.paths = paths
        self.minimumInterval = minimumInterval
        self.fallbackInterval = fallbackInterval
        reader = SnapshotReader(paths: paths)
    }

    public var isRunning: Bool { fallbackTask != nil }

    /// Começa a observar os arquivos e faz a primeira leitura.
    public func start() {
        guard fallbackTask == nil else { return }
        startWatcher()
        let interval = fallbackInterval
        fallbackTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.scheduleRefresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    public func stop() {
        fallbackTask?.cancel()
        fallbackTask = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        watcher = nil
    }

    /// Troca a pasta do Claude Code: descarta o cache e relê tudo.
    public func setPaths(_ newPaths: ClaudePaths) {
        guard newPaths != paths else { return }
        paths = newPaths
        reader = SnapshotReader(paths: newPaths)
        snapshot = AgentBarSnapshot()
        lastRefresh = nil
        if isRunning {
            startWatcher()
            scheduleRefresh()
        }
    }

    /// Lê agora, sem esperar o intervalo mínimo.
    public func refreshNow() async {
        let reader = self.reader
        let started = Date()
        lastRefreshStart = started
        let snapshot = await reader.read(now: started)
        // Uma troca de pasta no meio da leitura invalida o resultado.
        guard reader === self.reader else { return }
        if snapshot != self.snapshot { self.snapshot = snapshot }
        lastRefresh = started
    }

    private func scheduleRefresh() {
        guard pendingRefresh == nil else { return }
        let sinceLast = lastRefreshStart.map { Date().timeIntervalSince($0) } ?? .infinity
        let delay = max(0, minimumInterval - sinceLast)
        pendingRefresh = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            await self?.refreshNow()
            self?.pendingRefresh = nil
        }
    }

    private func startWatcher() {
        watcher = FileWatcher(root: paths.root) { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
    }
}
