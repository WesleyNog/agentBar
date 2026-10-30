import AgentBarCore
import Foundation

// Mostra no terminal o que o AgentBar está lendo. Útil para conferir números e
// para diagnosticar quando uma versão nova do Claude Code muda algum formato.

let usage = """
Uso: agentbar-dump [opções]

  --json                 saída em JSON
  --claude-dir <pasta>   pasta do Claude Code (padrão: CLAUDE_CONFIG_DIR ou ~/.claude)
  --rate-limits <arq>    lê os limites só deste arquivo em vez dos salvos pelo AgentBar
  --hours <n>            janela dos workflows que já terminaram (padrão: 24)
  -h, --help             esta ajuda
"""

struct Options {
    var json = false
    var paths = ClaudePaths.standard()
    var rateLimitsFile: URL?
    var hours: Double = 24
}

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var iterator = arguments.makeIterator()
    func value(for flag: String) -> String {
        guard let value = iterator.next() else { fail("falta o valor de \(flag)") }
        return value
    }
    while let argument = iterator.next() {
        switch argument {
        case "--json": options.json = true
        case "--claude-dir": options.paths = ClaudePaths(root: url(value(for: argument)))
        case "--rate-limits": options.rateLimitsFile = url(value(for: argument))
        case "--hours":
            guard let hours = Double(value(for: argument)), hours > 0 else { fail("--hours precisa ser um número positivo") }
            options.hours = hours
        case "-h", "--help":
            print(usage)
            exit(0)
        default: fail("opção desconhecida: \(argument)")
        }
    }
    return options
}

func url(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("agentbar-dump: \(message)\n\n\(usage)\n".utf8))
    exit(2)
}

// MARK: - Leitura

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))
let now = Date()
let rateLimitsSource = (options.rateLimitsFile ?? options.paths.rateLimitsDirectory).path
let rateLimits = if let file = options.rateLimitsFile {
    RateLimitsReader.read(at: file)
} else {
    RateLimitsReader.readMerged(directory: options.paths.rateLimitsDirectory, legacyFile: options.paths.legacyRateLimitsFile)
}
let statusLine = Result { try StatusLineInstaller(paths: options.paths).state() }
let sessions = SessionRegistry.load(from: options.paths.sessionsDirectory)
let runs = WorkflowScanner(paths: options.paths, recentWindow: options.hours * 3600).scan(sessions: sessions, now: now)

// MARK: - Saída em texto

func dateText(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).hour().minute())
}

func windowLine(_ title: String, _ window: RateLimitWindow?) -> String {
    guard let window else { return "  \(title)  --" }
    let percent = PercentFormat.short(window.effectivePercentage(now: now)).padding(toLength: 5, withPad: " ", startingAt: 0)
    let reset = window.resetsAt > now
        ? "reseta \(dateText(window.resetsAt)) (em \(DisplayFormat.duration(window.resetsAt.timeIntervalSince(now))))"
        : "resetou em \(dateText(window.resetsAt))"
    return "  \(title)  \(percent) \(reset)"
}

func statusSymbol(_ status: WorkflowStatus) -> String {
    switch status {
    case .running: "●"
    case .completed: "✓"
    case .stopped: "■"
    case .failed: "✗"
    case .interrupted: "⚠"
    case .other: "?"
    }
}

func statusText(_ status: WorkflowStatus) -> String {
    switch status {
    case .running: "rodando"
    case .completed: "concluído"
    case .stopped: "parado"
    case .failed: "falhou"
    case .interrupted: "interrompido"
    case .other(let raw): "status \"\(raw)\""
    }
}

func agentText(_ agent: WorkflowAgent) -> String {
    let symbol = switch agent.state {
    case .running: "●"
    case .done: "✓"
    case .failed: "✗"
    case .stopped: "■"
    }
    var details: [String] = []
    if let model = agent.model { details.append(DisplayFormat.modelName(model)) }
    if let tokens = agent.tokens { details.append("\(DisplayFormat.tokens(tokens)) tok") }
    if let start = agent.startedAt {
        details.append(DisplayFormat.duration((agent.endedAt ?? now).timeIntervalSince(start)))
    }
    if agent.state == .running, let last = agent.lastActivityAt, now.timeIntervalSince(last) >= 30 {
        details.append("idle \(DisplayFormat.duration(now.timeIntervalSince(last)))")
    }
    return "      \(symbol) \(agent.label.padding(toLength: 28, withPad: " ", startingAt: 0)) \(details.joined(separator: " · "))"
}

func printText() {
    print("AgentBar · \(options.paths.root.path)\n")

    if let rateLimits {
        print("Limites (atualizado há \(DisplayFormat.duration(now.timeIntervalSince(rateLimits.updatedAt))))")
        print(windowLine("Sessão (5h)", rateLimits.limits.fiveHour))
        print(windowLine("Semana (7d)", rateLimits.limits.sevenDay))
    } else {
        print("Limites: sem dados em \(rateLimitsSource)")
    }
    switch statusLine {
    case .success(.connected): print("  status line: conectado ao AgentBar")
    case .success(.otherCommand(let command)): print("  status line: outro comando (\(command))")
    case .success(.notConfigured): print("  status line: não configurado")
    case .failure(let error): print("  status line: settings.json ilegível (\(error))")
    }

    let alive = sessions.filter(\.isAlive)
    print("\nSessões do Claude Code: \(sessions.count) registradas, \(alive.count) vivas")
    for session in sessions {
        let folder = session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?"
        let state = session.isAlive ? (session.status ?? "?") : "morta"
        print("  \(String(session.pid).padding(toLength: 7, withPad: " ", startingAt: 0)) \(state.padding(toLength: 8, withPad: " ", startingAt: 0)) \(folder)")
    }

    let running = runs.filter { $0.status == .running }.count
    print("\nWorkflows (\(Int(options.hours))h): \(running) rodando · \(runs.count - running) terminados")
    for run in runs {
        var details: [String] = []
        if let project = run.projectName { details.append(project) }
        details.append(statusText(run.status))
        if let elapsed = run.elapsed(now: now) { details.append(DisplayFormat.duration(elapsed)) }
        details.append("\(run.doneAgentCount)/\(run.agents.count) agentes")
        details.append("\(DisplayFormat.tokens(run.totalTokens)) tok")
        print("\n  \(statusSymbol(run.status)) \(run.name)  (\(run.id))")
        print("    \(details.joined(separator: " · "))")
        if let description = run.description { print("    \(description)") }
        let phases = run.phaseProgress.map { "\($0.phase.title) \($0.done)/\($0.total)" }
        if !phases.isEmpty { print("    fases: \(phases.joined(separator: " · "))") }
        run.agents.forEach { print(agentText($0)) }
    }
}

// MARK: - Saída em JSON

struct Dump: Encodable {
    struct Window: Encodable {
        let usedPercentage: Double
        let effectivePercentage: Double
        let resetsAt: Date
    }

    struct Session: Encodable {
        let pid: Int32
        let sessionId: String
        let cwd: String?
        let status: String?
        let isAlive: Bool
    }

    struct Agent: Encodable {
        let id, label: String
        let phase, model: String?
        let state: String
        let tokens: Int?
        let startedAt, lastActivityAt, endedAt: Date?
    }

    struct Run: Encodable {
        let id, name, sessionId, status: String
        let description, projectName: String?
        let startedAt, endedAt: Date?
        let totalTokens, doneAgents, agentCount: Int
        let phases: [String]
        let agents: [Agent]
    }

    let claudeDirectory: String
    let rateLimitsSource: String
    let rateLimitsUpdatedAt: Date?
    let fiveHour, sevenDay: Window?
    let statusLine: String
    let sessions: [Session]
    let workflows: [Run]
}

func printJSON() throws {
    func window(_ window: RateLimitWindow?) -> Dump.Window? {
        window.map { Dump.Window(usedPercentage: $0.usedPercentage, effectivePercentage: $0.effectivePercentage(now: now), resetsAt: $0.resetsAt) }
    }
    let statusLineText = switch statusLine {
    case .success(.connected): "connected"
    case .success(.otherCommand): "other"
    case .success(.notConfigured): "none"
    case .failure: "invalid-settings"
    }
    let dump = Dump(
        claudeDirectory: options.paths.root.path,
        rateLimitsSource: rateLimitsSource,
        rateLimitsUpdatedAt: rateLimits?.updatedAt,
        fiveHour: window(rateLimits?.limits.fiveHour),
        sevenDay: window(rateLimits?.limits.sevenDay),
        statusLine: statusLineText,
        sessions: sessions.map { Dump.Session(pid: $0.pid, sessionId: $0.sessionId, cwd: $0.cwd, status: $0.status, isAlive: $0.isAlive) },
        workflows: runs.map { run in
            Dump.Run(
                id: run.id, name: run.name, sessionId: run.sessionId, status: statusText(run.status),
                description: run.description, projectName: run.projectName,
                startedAt: run.startedAt, endedAt: run.endedAt,
                totalTokens: run.totalTokens, doneAgents: run.doneAgentCount, agentCount: run.agents.count,
                phases: run.phases.map(\.title),
                agents: run.agents.map { agent in
                    Dump.Agent(
                        id: agent.id, label: agent.label, phase: agent.phase, model: agent.model,
                        state: "\(agent.state)", tokens: agent.tokens,
                        startedAt: agent.startedAt, lastActivityAt: agent.lastActivityAt, endedAt: agent.endedAt
                    )
                }
            )
        }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: try encoder.encode(dump), as: UTF8.self))
}

if options.json {
    do {
        try printJSON()
    } catch {
        fail("não consegui gerar o JSON: \(error)")
    }
} else {
    printText()
}
