import Foundation
import Testing
@testable import AgentBarCore

@Suite("ScriptMetaParser")
struct ScriptMetaParserTests {
    @Test func leOMetaDeUmScript() {
        let source = """
        export const meta = {
          name: 'revisar-coisas',
          description: 'Revisão adversarial: 3 lentes + verificação',
          phases: [
            { title: 'Revisão', detail: '3 lentes: porta, cadastro, regressões' },
            { title: 'Verificação' },
          ],
        }

        const CONTEXTO = `Você revisa ${algo}`
        """

        #expect(ScriptMetaParser.parse(source) == WorkflowScriptMeta(
            name: "revisar-coisas",
            description: "Revisão adversarial: 3 lentes + verificação",
            phases: [
                WorkflowPhase(title: "Revisão", detail: "3 lentes: porta, cadastro, regressões"),
                WorkflowPhase(title: "Verificação"),
            ]
        ))
    }

    @Test func aspasEscapesComentariosEOutrosValores() {
        let source = #"""
        export   const meta={
          // nome com aspas
          "name": "diz \"oi\" e café",
          description: 'it\'s', /* bloco */
          phases: [{ detail: `sem título` }, { "title": "Única" }],
          version: 2, enabled: true, extra: null, tags: ['a', 'b'],
        };
        """#

        #expect(ScriptMetaParser.parse(source) == WorkflowScriptMeta(
            name: #"diz "oi" e café"#,
            description: "it's",
            phases: [WorkflowPhase(title: "Única")]
        ))
    }

    @Test(arguments: [
        "const x = 1",
        "export const meta = {",
        "export const meta = { name: 'a' description: 'b' }",
        "export const meta = buildMeta()",
    ])
    func semMetaLegivelViraNil(source: String) {
        #expect(ScriptMetaParser.parse(source) == nil)
    }

    @Test func nomePeloArquivo() {
        #expect(ScriptMetaParser.name(fromScriptFile: "revisar-x-wf_ab12-c3.js", runId: "wf_ab12-c3") == "revisar-x")
        #expect(ScriptMetaParser.name(fromScriptFile: "-wf_ab12-c3.js", runId: "wf_ab12-c3") == nil)
        #expect(ScriptMetaParser.name(fromScriptFile: "outro.js", runId: "wf_ab12-c3") == nil)
    }
}

@Suite("JournalParser")
struct JournalParserTests {
    @Test func ultimoEventoDefineOEstado() {
        let journal = """
        {"type":"launched"}
        {"type":"started","key":"v2:1","agentId":"a1","label":"revisão:porta","phase":"Revisão"}
        {"type":"started","key":"v2:2","agentId":"a2","label":"revisão:cadastro","phase":"Revisão"}
        {"type":"started","key":"v2:3","agentId":"a3","label":"verifica:1","phase":"Verificação"}
        {"type":"result","key":"v2:1","agentId":"a1","result":{"findings":[]},"toolsUsed":["Read"]}
        {"type":"failed","key":"v2:2","agentId":"a2"}
        {"type":"evento-novo","agentId":"a3"}
        {"type":"result","key":"v2:3","agentId":"a3","res
        """

        #expect(JournalParser.agents(in: Data(journal.utf8)) == [
            JournalAgent(id: "a1", label: "revisão:porta", phase: "Revisão", state: .done),
            JournalAgent(id: "a2", label: "revisão:cadastro", phase: "Revisão", state: .failed),
            JournalAgent(id: "a3", label: "verifica:1", phase: "Verificação", state: .running),
        ])
    }

    @Test func journalVazio() {
        #expect(JournalParser.agents(in: Data()).isEmpty)
    }

    /// Ao retomar, o Claude Code começa de novo, com a mesma `key`, os passos que não terminaram.
    @Test func retomadaSubstituiOAgenteQueNaoTerminou() {
        let journal = """
        {"type":"launched"}
        {"type":"started","key":"v2:1","agentId":"a1","label":"T1","phase":"Aplicar"}
        {"type":"started","key":"v2:2","agentId":"a2","label":"T2","phase":"Aplicar"}
        {"type":"result","key":"v2:1","agentId":"a1"}
        {"type":"started","key":"v2:2","agentId":"b2","label":"T2","phase":"Aplicar"}
        {"type":"failed","key":"v2:2","agentId":"a2"}
        {"type":"started","key":"v2:1","agentId":"c1","label":"T1","phase":"Aplicar"}
        """

        #expect(JournalParser.agents(in: Data(journal.utf8)) == [
            JournalAgent(id: "a1", label: "T1", phase: "Aplicar", state: .done),
            JournalAgent(id: "b2", label: "T2", phase: "Aplicar", state: .running),
            JournalAgent(id: "c1", label: "T1", phase: "Aplicar", state: .running),
        ])
    }
}

@Suite("IncrementalLineReader")
struct IncrementalLineReaderTests {
    @Test func entregaSoAsLinhasNovasEGuardaALinhaIncompleta() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let url = try dir.write("a\nb\nc", to: "t.jsonl")
        let reader = IncrementalLineReader(url: url)

        #expect(reader.readNewLines().lines.map(text) == ["a", "b"])
        #expect(reader.readNewLines().lines.isEmpty)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("-fim\nd\n".utf8))
        try handle.close()

        let chunk = reader.readNewLines()
        #expect(chunk.lines.map(text) == ["c-fim", "d"])
        #expect(!chunk.restarted)
    }

    @Test func arquivoQueEncolheRecomecaDoInicio() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let url = try dir.write("primeira linha comprida\nsegunda\n", to: "t.jsonl")
        let reader = IncrementalLineReader(url: url)
        _ = reader.readNewLines()

        try dir.write("x\n", to: "t.jsonl")
        let chunk = reader.readNewLines()

        #expect(chunk.restarted)
        #expect(chunk.lines.map(text) == ["x"])
    }

    @Test func arquivoAusente() {
        let reader = IncrementalLineReader(url: URL(fileURLWithPath: "/tmp/nao-existe-\(UUID().uuidString)"))
        #expect(reader.readNewLines().lines.isEmpty)
    }

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }
}

@Suite("AgentTranscript")
struct AgentTranscriptTests {
    @Test func tokensSaoOContextoDaUltimaResposta() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let url = try dir.write(
            [
                FakeTranscript.user(at: "2026-10-30T01:00:00.000Z", cwd: "/Users/ana/projetos/app"),
                FakeTranscript.assistant(at: "2026-10-30T01:00:05.000Z", model: "claude-opus-5-5", input: 2, cacheCreation: 1_000, cacheRead: 10_000, output: 500),
                FakeTranscript.assistant(at: "2026-10-30T01:00:06.000Z", model: "<synthetic>", input: 0, cacheCreation: 0, cacheRead: 0, output: 0),
            ].joined(separator: "\n") + "\n",
            to: "agent-a1.jsonl"
        )
        let reader = AgentTranscriptReader(url: url)

        var summary = reader.refresh()
        #expect(summary.model == "claude-opus-5-5")
        #expect(summary.contextTokens == 11_002)
        #expect(summary.cwd == "/Users/ana/projetos/app")
        #expect(summary.firstTimestamp == Timestamps.parseISO8601("2026-10-30T01:00:00.000Z"))
        #expect(summary.lastTimestamp == Timestamps.parseISO8601("2026-10-30T01:00:06.000Z"))

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((FakeTranscript.assistant(at: "2026-10-30T01:01:00Z", model: "claude-sonnet-5-5", input: 3, cacheCreation: 2_000, cacheRead: 11_000, output: 10) + "\n").utf8))
        try handle.close()

        summary = reader.refresh()
        #expect(summary.model == "claude-sonnet-5-5")
        #expect(summary.contextTokens == 13_003)
        #expect(summary.firstTimestamp == Timestamps.parseISO8601("2026-10-30T01:00:00.000Z"))
    }

    @Test func paradoNoLimiteDeUsoAteAProximaLinha() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let url = try dir.write(
            [
                FakeTranscript.assistant(at: "2026-10-30T01:00:05.000Z", model: "claude-opus-5-5", input: 2, cacheCreation: 1_000, cacheRead: 10_000, output: 500),
                FakeTranscript.apiRequest(at: "2026-10-30T01:00:06.000Z"),
                FakeTranscript.usageLimit(at: "2026-10-30T01:00:07.000Z", resetsAt: 1_793_466_600),
            ].joined(separator: "\n") + "\n",
            to: "agent-a1.jsonl"
        )
        let reader = AgentTranscriptReader(url: url)

        var summary = reader.refresh()
        #expect(summary.usageLimit == UsageLimitStop(resetsAt: Date(timeIntervalSince1970: 1_793_466_600)))
        #expect(summary.model == "claude-opus-5-5")
        #expect(summary.contextTokens == 11_002)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((FakeTranscript.apiRequest(at: "2026-10-30T01:05:00.000Z") + "\n").utf8))
        try handle.close()

        summary = reader.refresh()
        #expect(summary.usageLimit == nil)
    }
}

/// Linhas sintéticas no formato dos transcripts do Claude Code.
enum FakeTranscript {
    static func user(at timestamp: String, cwd: String) -> String {
        #"{"type":"user","timestamp":"\#(timestamp)","cwd":"\#(cwd)","message":{"role":"user","content":"Tarefa"}}"#
    }

    static func assistant(at timestamp: String, model: String, input: Int, cacheCreation: Int, cacheRead: Int, output: Int) -> String {
        #"{"type":"assistant","timestamp":"\#(timestamp)","cwd":"/x","message":{"id":"msg_\#(timestamp)","model":"\#(model)","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheCreation),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output)}}}"#
    }

    static func apiRequest(at timestamp: String) -> String {
        #"{"type":"api-request","timestamp":"\#(timestamp)","cwd":"/x"}"#
    }

    /// A resposta sintética que o Claude Code grava quando o limite de uso estoura.
    static func usageLimit(at timestamp: String, resetsAt: Int) -> String {
        #"{"type":"assistant","timestamp":"\#(timestamp)","cwd":"/x","isApiErrorMessage":true,"error":"rate_limit","apiError":"usage_limit_reached","apiErrorStatus":429,"apiErrorParams":{"rate_limit_info":{"status":"rejected","resetsAt":\#(resetsAt),"rateLimitType":"five_hour"}},"quotaLimits":{"status":"rejected","resetsAt":\#(resetsAt),"rateLimitType":"five_hour"},"message":{"id":"msg_x","model":"<synthetic>","content":[{"type":"text","text":"You've hit your 5-hour limit"}],"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}"#
    }
}
