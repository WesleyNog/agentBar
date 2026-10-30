import Foundation
import Testing
@testable import AgentBarCore

@Suite("SessionRegistry")
struct SessionRegistryTests {
    private static let session = #"""
    {"pid":25704,"sessionId":"5f0c2a1e-7b3d-4e8a-9c61-2d4b8e7f1a30","cwd":"/Users/ana/projetos/app","startedAt":1793326205879,
     "procStart":"Fri Oct 30 02:10:04 2026","version":"2.1.312","kind":"interactive","name":"app-1f","status":"busy"}
    """#

    @Test func leASessaoEPassaOInicioDoProcessoParaAChecagem() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write(Self.session, to: "25704.json")
        try dir.write("chave", to: "25704.abc.key")

        let sessions = SessionRegistry.load(from: dir.url) { pid, startedAt in
            pid == 25704 && startedAt == Date(timeIntervalSince1970: 1_793_326_204)
        }

        #expect(sessions == [
            ClaudeSession(
                sessionId: "5f0c2a1e-7b3d-4e8a-9c61-2d4b8e7f1a30",
                pid: 25704,
                cwd: "/Users/ana/projetos/app",
                name: "app-1f",
                status: "busy",
                isAlive: true
            ),
        ])
    }

    @Test func processoMortoFicaComoNaoViva() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write(Self.session, to: "25704.json")

        let sessions = SessionRegistry.load(from: dir.url) { _, _ in false }

        #expect(sessions.map(\.isAlive) == [false])
    }

    @Test func arquivosIlegiveisSaoIgnorados() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write(Self.session, to: "25704.json")
        try dir.write("{quebrado", to: "1.json")
        try dir.write(#"{"pid":2}"#, to: "2.json")

        let sessions = SessionRegistry.load(from: dir.url) { _, _ in true }

        #expect(sessions.map(\.pid) == [25704])
    }

    @Test func pastaAusenteViraListaVazia() {
        let missing = URL(fileURLWithPath: "/tmp/agentbar-nao-existe-\(UUID().uuidString)")
        #expect(SessionRegistry.load(from: missing).isEmpty)
    }

    @Test(arguments: [
        ("Fri Oct 30 02:10:04 2026", 1_793_326_204.0),
        ("Sat Oct  3 09:05:00 2026", 1_791_018_300.0),
    ])
    func interpretaProcStartEmUTC(text: String, expected: TimeInterval) {
        #expect(SessionRegistry.parseProcStart(text) == Date(timeIntervalSince1970: expected))
    }

    @Test func procStartInvalidoViraNil() {
        #expect(SessionRegistry.parseProcStart("ontem à tarde") == nil)
    }
}

@Suite("ProcessProbe")
struct ProcessProbeTests {
    @Test func processoAtualEstaRodando() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let start = try #require(ProcessProbe.startTime(of: pid))

        #expect(start < .now)
        #expect(ProcessProbe.isRunning(pid: pid, startedAt: nil))
        #expect(ProcessProbe.isRunning(pid: pid, startedAt: start))
    }

    @Test func pidReaproveitadoNaoContaComoVivo() {
        let pid = ProcessInfo.processInfo.processIdentifier
        #expect(!ProcessProbe.isRunning(pid: pid, startedAt: Date(timeIntervalSince1970: 0)))
    }

    @Test func processoQueJaTerminou() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()

        #expect(!ProcessProbe.isRunning(pid: process.processIdentifier, startedAt: nil))
        #expect(!ProcessProbe.isRunning(pid: 0, startedAt: nil))
    }
}
