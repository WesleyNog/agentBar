import Foundation

/// Encontra os workflows em `~/.claude/projects` e monta o estado de cada um.
///
/// Guarda estado entre chamadas: execuções concluídas não mudam mais e ficam em cache,
/// e os transcripts dos agentes em andamento são lidos de forma incremental.
/// Não é thread-safe: use sempre da mesma fila ou actor.
public final class WorkflowScanner {
    public let paths: ClaudePaths
    /// Por quanto tempo um workflow que terminou continua aparecendo.
    public var recentWindow: TimeInterval

    /// Execuções terminadas, com a data do arquivo final que as gerou.
    private var finishedRuns: [String: (run: WorkflowRun, finalModified: Date)] = [:]
    private var transcripts: [URL: AgentTranscriptReader] = [:]
    private var scriptMetas: [String: (fileName: String, meta: WorkflowScriptMeta?)] = [:]
    private var projectNames: [URL: String] = [:]

    public init(paths: ClaudePaths, recentWindow: TimeInterval = 24 * 3600) {
        self.paths = paths
        self.recentWindow = recentWindow
    }

    /// Workflows rodando ou pausados primeiro (mais novo antes), depois os que terminaram (mais recente antes).
    public func scan(sessions: [ClaudeSession], now: Date = .now) -> [WorkflowRun] {
        let liveSessions = Dictionary(
            sessions.filter(\.isAlive).map { ($0.sessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var runs: [WorkflowRun] = []
        var usedTranscripts: Set<URL> = []

        for projectDirectory in FileInfo.contents(of: paths.projectsDirectory) {
            for sessionDirectory in FileInfo.contents(of: projectDirectory) {
                let runsDirectory = sessionDirectory.appendingPathComponent("subagents/workflows", isDirectory: true)
                guard FileInfo.isDirectory(runsDirectory) else { continue }
                let session = liveSessions[sessionDirectory.lastPathComponent]

                for runDirectory in FileInfo.contents(of: runsDirectory) where runDirectory.lastPathComponent.hasPrefix("wf_") {
                    let location = RunLocation(
                        runDirectory: runDirectory,
                        sessionDirectory: sessionDirectory,
                        projectDirectory: projectDirectory
                    )
                    if let run = scanRun(at: location, liveSession: session, now: now, usedTranscripts: &usedTranscripts) {
                        runs.append(run)
                    }
                }
            }
        }

        transcripts = transcripts.filter { usedTranscripts.contains($0.key) }
        return runs.sorted(by: Self.displayOrder)
    }

    // MARK: - Uma execução

    private struct RunLocation {
        let runDirectory: URL
        let sessionDirectory: URL
        let projectDirectory: URL

        var runId: String { runDirectory.lastPathComponent }
        var sessionId: String { sessionDirectory.lastPathComponent }
        var finalFile: URL { sessionDirectory.appendingPathComponent("workflows/\(runId).json") }
        var journal: URL { runDirectory.appendingPathComponent("journal.jsonl") }
        var scriptsDirectory: URL { sessionDirectory.appendingPathComponent("workflows/scripts", isDirectory: true) }

        func transcript(agentId: String) -> URL {
            runDirectory.appendingPathComponent("agent-\(agentId).jsonl")
        }
    }

    private func scanRun(
        at location: RunLocation,
        liveSession: ClaudeSession?,
        now: Date,
        usedTranscripts: inout Set<URL>
    ) -> WorkflowRun? {
        if let finalModified = FileInfo.modificationDate(of: location.finalFile),
           !wasResumed(at: location, finalModified: finalModified) {
            if let cached = finishedRuns[location.runId], cached.finalModified == finalModified {
                guard isRecent(cached.run, now: now) else {
                    finishedRuns[location.runId] = nil
                    return nil
                }
                return cached.run
            }
            // Arquivo final antigo nem é aberto.
            guard now.timeIntervalSince(finalModified) <= recentWindow,
                  let run = finishedRun(at: location, liveSession: liveSession),
                  isRecent(run, now: now)
            else { return nil }
            finishedRuns[location.runId] = (run, finalModified)
            return run
        }
        finishedRuns[location.runId] = nil

        if liveSession == nil {
            let lastChange = FileInfo.modificationDate(of: location.journal) ?? FileInfo.modificationDate(of: location.runDirectory)
            if let lastChange, now.timeIntervalSince(lastChange) > recentWindow { return nil }
        }
        return liveRun(at: location, liveSession: liveSession, usedTranscripts: &usedTranscripts)
    }

    /// Para retomar um workflow, o Claude Code grava o arquivo final (`killed`) e continua no mesmo journal.
    /// Num workflow que terminou, o journal nunca é gravado depois do arquivo final. Um concluído não é
    /// retomado, então o status protege contra datas mexidas, como numa cópia da pasta.
    private func wasResumed(at location: RunLocation, finalModified: Date) -> Bool {
        guard let journalModified = FileInfo.modificationDate(of: location.journal),
              journalModified.timeIntervalSince(finalModified) > 1,
              let data = try? Data(contentsOf: location.finalFile),
              let file = try? JSONDecoder().decode(FinalWorkflowFile.self, from: data)
        else { return false }
        return file.status != "completed"
    }

    /// Workflow terminado: tudo vem do arquivo final.
    private func finishedRun(at location: RunLocation, liveSession: ClaudeSession?) -> WorkflowRun? {
        guard let data = try? Data(contentsOf: location.finalFile),
              let file = try? JSONDecoder().decode(FinalWorkflowFile.self, from: data)
        else { return nil }

        let meta = file.script.flatMap(ScriptMetaParser.parse)
        let startedAt = file.startTime.map(Timestamps.fromMilliseconds)
        let endedAt = startedAt.flatMap { start in file.durationMs.map { start.addingTimeInterval($0 / 1000) } }
            ?? file.timestamp.flatMap(Timestamps.parseISO8601)
            ?? FileInfo.modificationDate(of: location.finalFile)

        let agents: [WorkflowAgent] = file.progress
            .filter { $0.type == "workflow_agent" }
            .enumerated()
            .map { position, entry in
                let id = entry.agentId ?? "index-\(entry.index ?? position)"
                let agentStart = (entry.startedAt ?? entry.queuedAt).map(Timestamps.fromMilliseconds)
                let lastProgress = entry.lastProgressAt.map(Timestamps.fromMilliseconds)
                return WorkflowAgent(
                    id: id,
                    label: entry.label ?? id,
                    phase: entry.phaseTitle,
                    state: AgentState(finalState: entry.state),
                    model: entry.model,
                    tokens: entry.tokens,
                    startedAt: agentStart,
                    lastActivityAt: lastProgress,
                    endedAt: agentStart.flatMap { start in entry.durationMs.map { start.addingTimeInterval($0 / 1000) } }
                        ?? lastProgress
                )
            }

        let phases = file.phases.compactMap { phase in phase.title.map { WorkflowPhase(title: $0, detail: phase.detail) } }

        return WorkflowRun(
            id: location.runId,
            name: file.workflowName ?? meta?.name ?? scriptInfo(at: location).name ?? location.runId,
            description: meta?.description,
            projectName: projectName(at: location, liveSession: liveSession, transcriptCwd: nil),
            sessionId: location.sessionId,
            status: WorkflowStatus(finalStatus: file.status),
            startedAt: startedAt,
            endedAt: endedAt,
            phases: phases.isEmpty ? (meta?.phases ?? []) : phases,
            agents: agents
        )
    }

    /// Workflow sem arquivo final, ou retomado depois dele: rodando ou pausado (sessão viva), ou interrompido (sessão morta).
    private func liveRun(
        at location: RunLocation,
        liveSession: ClaudeSession?,
        usedTranscripts: inout Set<URL>
    ) -> WorkflowRun {
        let isAlive = liveSession != nil
        let journalAgents = JournalParser.agents(in: (try? Data(contentsOf: location.journal)) ?? Data())
        var transcriptCwd: String?
        var usageLimitResets: [Date] = []

        let agents: [WorkflowAgent] = journalAgents.map { journalAgent in
            let url = location.transcript(agentId: journalAgent.id)
            usedTranscripts.insert(url)
            let reader = transcripts[url] ?? AgentTranscriptReader(url: url)
            transcripts[url] = reader
            let summary = reader.refresh()
            transcriptCwd = transcriptCwd ?? summary.cwd

            var state = journalAgent.state
            if state == .running, let usageLimit = summary.usageLimit {
                state = .paused
                if let resetsAt = usageLimit.resetsAt { usageLimitResets.append(resetsAt) }
            }
            if !isAlive, state == .running || state == .paused { state = .stopped }
            let lastActivity = summary.lastTimestamp ?? FileInfo.modificationDate(of: url)
            return WorkflowAgent(
                id: journalAgent.id,
                label: journalAgent.label ?? journalAgent.id,
                phase: journalAgent.phase,
                state: state,
                model: summary.model,
                tokens: summary.contextTokens,
                startedAt: summary.firstTimestamp,
                lastActivityAt: lastActivity,
                endedAt: state == .running ? nil : lastActivity
            )
        }

        let script = scriptInfo(at: location)
        // O journal nasce no lançamento; o primeiro agente cobre o caso de o arquivo ter sido copiado ou recriado.
        let startedAt = ([FileInfo.creationDate(of: location.journal)] + agents.map(\.startedAt)).compactMap { $0 }.min()
        let endedAt = isAlive ? nil : (agents.compactMap(\.lastActivityAt).max() ?? FileInfo.modificationDate(of: location.journal))

        return WorkflowRun(
            id: location.runId,
            name: script.meta?.name ?? script.name ?? location.runId,
            description: script.meta?.description,
            projectName: projectName(at: location, liveSession: liveSession, transcriptCwd: transcriptCwd),
            sessionId: location.sessionId,
            status: Self.liveStatus(isAlive: isAlive, agents: agents, usageLimitResets: usageLimitResets),
            startedAt: startedAt,
            endedAt: endedAt,
            phases: script.meta?.phases ?? [],
            agents: agents
        )
    }

    /// Pausado quando todos os agentes em andamento pararam no limite de uso, como no painel do Claude Code.
    private static func liveStatus(isAlive: Bool, agents: [WorkflowAgent], usageLimitResets: [Date]) -> WorkflowStatus {
        guard isAlive else { return .interrupted }
        let pending = agents.filter { $0.state == .running || $0.state == .paused }
        guard !pending.isEmpty, pending.allSatisfy({ $0.state == .paused }) else { return .running }
        return .paused(resetsAt: usageLimitResets.max())
    }

    // MARK: - Script e projeto

    /// O script fica em `workflows/scripts/<nome>-<runId>.js`.
    private func scriptInfo(at location: RunLocation) -> (name: String?, meta: WorkflowScriptMeta?) {
        if let cached = scriptMetas[location.runId] {
            return (ScriptMetaParser.name(fromScriptFile: cached.fileName, runId: location.runId), cached.meta)
        }
        let suffix = "-\(location.runId).js"
        guard let script = FileInfo.contents(of: location.scriptsDirectory).first(where: { $0.lastPathComponent.hasSuffix(suffix) }) else {
            return (nil, nil)
        }
        let meta = (try? String(contentsOf: script, encoding: .utf8)).flatMap(ScriptMetaParser.parse)
        scriptMetas[location.runId] = (script.lastPathComponent, meta)
        return (ScriptMetaParser.name(fromScriptFile: script.lastPathComponent, runId: location.runId), meta)
    }

    /// Nome da pasta do projeto: pelo `cwd` da sessão viva, do transcript, ou pelo nome da pasta em `projects`.
    private func projectName(at location: RunLocation, liveSession: ClaudeSession?, transcriptCwd: String?) -> String? {
        if let cwd = liveSession?.cwd ?? transcriptCwd {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            projectNames[location.sessionDirectory] = name
            return name
        }
        if let cached = projectNames[location.sessionDirectory] { return cached }

        let transcript = FileInfo.contents(of: location.runDirectory).first { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("agent-") }
        let name = transcript.flatMap(Self.cwdFromFirstLines).map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? Self.projectName(fromDirectoryName: location.projectDirectory.lastPathComponent)
        projectNames[location.sessionDirectory] = name
        return name
    }

    /// Procura o `cwd` no primeiro megabyte do transcript.
    private static func cwdFromFirstLines(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1 << 20) else { return nil }
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A) {
            if let cwd = (try? decoder.decode(CwdLine.self, from: Data(line)))?.cwd { return cwd }
        }
        return nil
    }

    private struct CwdLine: Decodable {
        let cwd: String?
    }

    /// `-Users-ana-projetos-app` → `app`. Aproximado: nomes com hífen perdem o começo.
    static func projectName(fromDirectoryName name: String) -> String? {
        name.split(separator: "-").last.map(String.init)
    }

    // MARK: - Ordem e janela

    private func isRecent(_ run: WorkflowRun, now: Date) -> Bool {
        guard !run.status.isActive, let endedAt = run.endedAt else { return true }
        return now.timeIntervalSince(endedAt) <= recentWindow
    }

    private static func displayOrder(_ lhs: WorkflowRun, _ rhs: WorkflowRun) -> Bool {
        let lhsRunning = lhs.status.isActive
        let rhsRunning = rhs.status.isActive
        if lhsRunning != rhsRunning { return lhsRunning }
        let lhsDate = (lhsRunning ? lhs.startedAt : lhs.endedAt ?? lhs.startedAt) ?? .distantPast
        let rhsDate = (rhsRunning ? rhs.startedAt : rhs.endedAt ?? rhs.startedAt) ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return lhs.id < rhs.id
    }
}
