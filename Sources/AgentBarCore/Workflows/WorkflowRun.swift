import Foundation

public enum WorkflowStatus: Sendable, Equatable {
    case running
    case completed
    /// Parado pelo usuário (`killed` no arquivo final).
    case stopped
    case failed
    /// Sem arquivo final e a sessão dona morreu.
    case interrupted
    /// Status que o AgentBar não conhece, como veio do arquivo.
    case other(String)

    init(finalStatus: String?) {
        switch finalStatus {
        case "completed": self = .completed
        case "killed": self = .stopped
        case "failed", "error": self = .failed
        case let raw?: self = .other(raw)
        case nil: self = .other("")
        }
    }
}

public enum AgentState: Sendable, Equatable {
    case running
    case done
    case failed
    /// Não terminou porque o workflow acabou antes (parado ou interrompido).
    case stopped

    init(finalState: String?) {
        switch finalState {
        case "done": self = .done
        case "error", "failed": self = .failed
        default: self = .stopped
        }
    }
}

public struct WorkflowAgent: Sendable, Equatable, Identifiable {
    public let id: String
    public var label: String
    public var phase: String?
    public var state: AgentState
    public var model: String?
    /// Tamanho do contexto na última resposta, como o Claude Code mostra em "tok".
    public var tokens: Int?
    public var startedAt: Date?
    public var lastActivityAt: Date?
    public var endedAt: Date?

    public init(
        id: String,
        label: String,
        phase: String? = nil,
        state: AgentState,
        model: String? = nil,
        tokens: Int? = nil,
        startedAt: Date? = nil,
        lastActivityAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.phase = phase
        self.state = state
        self.model = model
        self.tokens = tokens
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.endedAt = endedAt
    }
}

public struct WorkflowPhase: Sendable, Equatable {
    public let title: String
    public let detail: String?

    public init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }
}

public struct PhaseProgress: Sendable, Equatable {
    public let phase: WorkflowPhase
    public let done: Int
    public let total: Int
}

public struct WorkflowRun: Sendable, Equatable, Identifiable {
    /// O `runId`, como `wf_995adbc7-fcb`.
    public let id: String
    public var name: String
    public var description: String?
    public var projectName: String?
    public var sessionId: String
    public var status: WorkflowStatus
    public var startedAt: Date?
    public var endedAt: Date?
    public var phases: [WorkflowPhase]
    public var agents: [WorkflowAgent]

    public init(
        id: String,
        name: String,
        description: String? = nil,
        projectName: String? = nil,
        sessionId: String,
        status: WorkflowStatus,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        phases: [WorkflowPhase] = [],
        agents: [WorkflowAgent] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.projectName = projectName
        self.sessionId = sessionId
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.phases = phases
        self.agents = agents
    }

    public var totalTokens: Int {
        agents.reduce(0) { $0 + ($1.tokens ?? 0) }
    }

    public var doneAgentCount: Int {
        agents.filter { $0.state == .done }.count
    }

    public func elapsed(now: Date = .now) -> TimeInterval? {
        guard let startedAt else { return nil }
        return (endedAt ?? now).timeIntervalSince(startedAt)
    }

    /// Progresso por fase, na ordem do script. Fases que só aparecem nos agentes vão no fim.
    public var phaseProgress: [PhaseProgress] {
        var phases = self.phases
        for title in agents.compactMap(\.phase) where !phases.contains(where: { $0.title == title }) {
            phases.append(WorkflowPhase(title: title))
        }
        return phases.map { phase in
            let inPhase = agents.filter { $0.phase == phase.title }
            return PhaseProgress(phase: phase, done: inPhase.filter { $0.state == .done }.count, total: inPhase.count)
        }
    }
}
