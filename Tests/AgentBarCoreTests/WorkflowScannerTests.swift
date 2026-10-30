import Foundation
import Testing
@testable import AgentBarCore

@Suite("WorkflowScanner")
struct WorkflowScannerTests {
    private static let project = "projects/-Users-ana-projetos-app"
    private let now = Date()

    private func iso(_ secondsAgo: TimeInterval) -> String {
        Date(timeInterval: -secondsAgo, since: now).formatted(.iso8601)
    }

    private func millis(_ secondsAgo: TimeInterval) -> Int {
        Int(Date(timeInterval: -secondsAgo, since: now).timeIntervalSince1970 * 1000)
    }

    private func session(_ id: String, alive: Bool) -> ClaudeSession {
        ClaudeSession(sessionId: id, pid: 1, cwd: "/Users/ana/projetos/app", name: nil, status: "busy", isAlive: alive)
    }

    /// S1 (viva): um rodando e um concluído. S2 (morta): um interrompido. S3: um concluído há 3 dias.
    private func makeHome() throws -> TempDirectory {
        let dir = try TempDirectory()
        let s1 = "\(Self.project)/S1"
        let s2 = "\(Self.project)/S2"
        let s3 = "\(Self.project)/S3"

        // Rodando.
        try dir.write("""
        export const meta = {
          name: 'revisar-coisas',
          description: 'Revisão com verificação',
          phases: [{ title: 'Revisão' }, { title: 'Verificação' }],
        }
        """, to: "\(s1)/workflows/scripts/revisar-coisas-wf_live.js")
        try dir.write("""
        {"type":"launched"}
        {"type":"started","agentId":"a1","label":"revisão:porta","phase":"Revisão"}
        {"type":"started","agentId":"a2","label":"revisão:cadastro","phase":"Revisão"}
        {"type":"result","agentId":"a1","result":{}}

        """, to: "\(s1)/subagents/workflows/wf_live/journal.jsonl")
        try dir.write(
            FakeTranscript.assistant(at: iso(300), model: "claude-opus-5-5", input: 1, cacheCreation: 99, cacheRead: 900, output: 5) + "\n",
            to: "\(s1)/subagents/workflows/wf_live/agent-a1.jsonl"
        )
        try dir.write(
            FakeTranscript.assistant(at: iso(60), model: "claude-opus-5-5", input: 1, cacheCreation: 199, cacheRead: 1_800, output: 5) + "\n",
            to: "\(s1)/subagents/workflows/wf_live/agent-a2.jsonl"
        )

        // Concluído há 1h30.
        try dir.write(#"{"type":"launched"}"#, to: "\(s1)/subagents/workflows/wf_done/journal.jsonl")
        try dir.write(finalFile(name: "plano-x", status: "completed", startedSecondsAgo: 7_200, durationSeconds: 1_800), to: "\(s1)/workflows/wf_done.json")

        // Interrompido: sessão morta, script sem meta.
        try dir.write("const x = 1", to: "\(s2)/workflows/scripts/orfao-wf_orphan.js")
        try dir.write(#"{"type":"started","agentId":"b1","label":"frente:1","phase":"Investigação"}"#, to: "\(s2)/subagents/workflows/wf_orphan/journal.jsonl")
        try dir.write(
            FakeTranscript.user(at: iso(900), cwd: "/Users/ana/projetos/outro-app") + "\n"
                + FakeTranscript.assistant(at: iso(600), model: "claude-sonnet-5-5", input: 1, cacheCreation: 0, cacheRead: 499, output: 5) + "\n",
            to: "\(s2)/subagents/workflows/wf_orphan/agent-b1.jsonl"
        )

        // Concluído há 3 dias: fora da janela.
        try dir.write(#"{"type":"launched"}"#, to: "\(s3)/subagents/workflows/wf_old/journal.jsonl")
        try dir.write(finalFile(name: "velho", status: "completed", startedSecondsAgo: 260_000, durationSeconds: 60), to: "\(s3)/workflows/wf_old.json")
        try dir.setModificationDate(now.addingTimeInterval(-259_000), of: "\(s3)/workflows/wf_old.json")

        return dir
    }

    private func finalFile(name: String, status: String, startedSecondsAgo: TimeInterval, durationSeconds: TimeInterval) -> String {
        let start = millis(startedSecondsAgo)
        return """
        {"runId":"x","workflowName":"\(name)","status":"\(status)","startTime":\(start),"durationMs":\(Int(durationSeconds * 1000)),
         "agentCount":2,"totalTokens":3000,"script":"export const meta = { name: '\(name)', description: 'Descrição de \(name)' }",
         "phases":[{"title":"Única","detail":"tudo"}],
         "result":{"qualquer":["coisa"]},
         "workflowProgress":[
           {"type":"workflow_phase","index":1,"title":"Única"},
           {"type":"workflow_agent","agentId":"c1","label":"frente:a","phaseTitle":"Única","model":"claude-opus-5-5","state":"done","startedAt":\(start),"durationMs":600000,"tokens":1000},
           {"type":"workflow_agent","agentId":"c2","label":"frente:b","phaseTitle":"Única","model":"claude-opus-5-5","state":"error","startedAt":\(start),"tokens":"2000"}
         ]}
        """
    }

    @Test func montaOsTresEstadosNaOrdemCerta() throws {
        let dir = try makeHome()
        defer { dir.remove() }
        let scanner = WorkflowScanner(paths: ClaudePaths(root: dir.url))

        let runs = scanner.scan(sessions: [session("S1", alive: true), session("S2", alive: false)], now: now)

        #expect(runs.map(\.id) == ["wf_live", "wf_orphan", "wf_done"])
        #expect(runs.map(\.status) == [.running, .interrupted, .completed])
    }

    @Test func workflowRodando() throws {
        let dir = try makeHome()
        defer { dir.remove() }
        let scanner = WorkflowScanner(paths: ClaudePaths(root: dir.url))

        let run = try #require(scanner.scan(sessions: [session("S1", alive: true)], now: now).first { $0.id == "wf_live" })

        #expect(run.name == "revisar-coisas")
        #expect(run.description == "Revisão com verificação")
        #expect(run.projectName == "app")
        #expect(run.endedAt == nil)
        #expect(run.agents.map(\.label) == ["revisão:porta", "revisão:cadastro"])
        #expect(run.agents.map(\.state) == [.done, .running])
        #expect(run.agents.map(\.tokens) == [1_000, 2_000])
        #expect(run.totalTokens == 3_000)
        #expect(run.doneAgentCount == 1)
        #expect(run.phaseProgress == [
            PhaseProgress(phase: WorkflowPhase(title: "Revisão"), done: 1, total: 2),
            PhaseProgress(phase: WorkflowPhase(title: "Verificação"), done: 0, total: 0),
        ])
    }

    @Test func workflowConcluidoVemDoArquivoFinal() throws {
        let dir = try makeHome()
        defer { dir.remove() }
        let scanner = WorkflowScanner(paths: ClaudePaths(root: dir.url))

        let run = try #require(scanner.scan(sessions: [], now: now).first { $0.id == "wf_done" })

        #expect(run.name == "plano-x")
        #expect(run.description == "Descrição de plano-x")
        #expect(run.phases == [WorkflowPhase(title: "Única", detail: "tudo")])
        #expect(run.agents.map(\.state) == [.done, .failed])
        // `tokens` com tipo errado no segundo agente não derruba o arquivo.
        #expect(run.agents.map(\.tokens) == [1_000, nil])
        #expect(try #require(run.elapsed(now: now)) == 1_800)
        #expect(run.agents.first?.endedAt == run.agents.first?.startedAt?.addingTimeInterval(600))
    }

    @Test func workflowDeSessaoMortaFicaInterrompido() throws {
        let dir = try makeHome()
        defer { dir.remove() }
        let scanner = WorkflowScanner(paths: ClaudePaths(root: dir.url))

        let run = try #require(scanner.scan(sessions: [session("S2", alive: false)], now: now).first { $0.id == "wf_orphan" })

        #expect(run.name == "orfao")
        #expect(run.projectName == "outro-app")
        #expect(run.agents.map(\.state) == [.stopped])
        #expect(run.agents.first?.model == "claude-sonnet-5-5")
        #expect(run.endedAt == Timestamps.parseISO8601(iso(600)))
    }

    @Test func acompanhaOTranscriptEOFimDoWorkflow() throws {
        let dir = try makeHome()
        defer { dir.remove() }
        let scanner = WorkflowScanner(paths: ClaudePaths(root: dir.url))
        let sessions = [session("S1", alive: true)]
        _ = scanner.scan(sessions: sessions, now: now)

        let transcript = dir.url.appendingPathComponent("\(Self.project)/S1/subagents/workflows/wf_live/agent-a2.jsonl")
        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((FakeTranscript.assistant(at: iso(10), model: "claude-opus-5-5", input: 1, cacheCreation: 499, cacheRead: 2_500, output: 5) + "\n").utf8))
        try handle.close()
        #expect(scanner.scan(sessions: sessions, now: now).first { $0.id == "wf_live" }?.agents.last?.tokens == 3_000)

        try dir.write(finalFile(name: "revisar-coisas", status: "killed", startedSecondsAgo: 400, durationSeconds: 390), to: "\(Self.project)/S1/workflows/wf_live.json")
        #expect(scanner.scan(sessions: sessions, now: now).first { $0.id == "wf_live" }?.status == .stopped)
    }

    @Test func semPastaDeProjetos() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }

        #expect(WorkflowScanner(paths: ClaudePaths(root: dir.url)).scan(sessions: [], now: now).isEmpty)
    }

    @Test func nomeDoProjetoPelaPasta() {
        #expect(WorkflowScanner.projectName(fromDirectoryName: "-Users-ana-projetos-app") == "app")
    }
}
