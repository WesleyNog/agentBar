import Foundation
import Testing
@testable import AgentBarCore

@Suite("ChangeFilter")
struct ChangeFilterTests {
    @Test(arguments: [
        ("/u/.claude/settings.json", true),
        ("/u/.claude/agentbar/rate_limits.json", true),
        ("/u/.claude/sessions/25704.json", true),
        ("/u/.claude/projects/-u-app/S1/subagents/workflows/wf_1/agent-a.jsonl", true),
        ("/u/.claude/projects/-u-app/S1/workflows/wf_1.json", true),
        ("/u/.claude/projects/-u-app/S1.jsonl", false),
        ("/u/.claude/history.jsonl", false),
        ("/u/.claude/settings.json.bak", false),
        ("/u/.claude-outro/settings.json", false),
        ("/u/.claude", false),
    ])
    func relevancia(path: String, expected: Bool) {
        #expect(ChangeFilter.isRelevant(path: path, root: "/u/.claude") == expected)
    }

    @Test func caminhoCanonicoResolveLinks() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        // A pasta temporária fica em /var, que é um link para /private/var.
        #expect(ChangeFilter.canonicalPath(dir.url).hasPrefix("/private/"))
    }
}

@Suite("AgentBarStore")
@MainActor
struct AgentBarStoreTests {
    private static let rateLimits = #"{"five_hour":{"used_percentage":27,"resets_at":1893456000},"seven_day":{"used_percentage":45,"resets_at":1893456000}}"#

    @Test func refreshLeTudo() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write(Self.rateLimits, to: "agentbar/rate_limits.json")
        try dir.write(#"{"statusLine":{"type":"command","command":"echo oi"}}"#, to: "settings.json")
        let store = AgentBarStore(paths: ClaudePaths(root: dir.url))

        await store.refreshNow()

        #expect(store.snapshot.rateLimits?.limits.fiveHour?.usedPercentage == 27)
        #expect(store.snapshot.statusLine == .otherCommand("echo oi"))
        #expect(store.snapshot.workflows.isEmpty)
        #expect(store.lastRefresh != nil)
    }

    @Test func settingsInvalidoViraEstadoNil() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("{quebrado", to: "settings.json")
        let store = AgentBarStore(paths: ClaudePaths(root: dir.url))

        await store.refreshNow()

        #expect(store.snapshot.statusLine == nil)
    }

    @Test func percebeArquivoNovoSemEsperarOTimer() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let store = AgentBarStore(paths: ClaudePaths(root: dir.url), minimumInterval: 0.2, fallbackInterval: 3600)
        store.start()
        defer { store.stop() }
        try await waitUntil { store.lastRefresh != nil }
        #expect(store.snapshot.rateLimits == nil)

        // A pasta agentbar ainda não existia quando o monitor começou.
        try dir.write(Self.rateLimits, to: "agentbar/rate_limits.json")

        try await waitUntil { store.snapshot.rateLimits != nil }
        #expect(store.snapshot.rateLimits?.limits.sevenDay?.usedPercentage == 45)
    }

    @Test func trocarDePastaRele() async throws {
        let first = try TempDirectory()
        let second = try TempDirectory()
        defer {
            first.remove()
            second.remove()
        }
        try second.write(Self.rateLimits, to: "agentbar/rate_limits.json")
        let store = AgentBarStore(paths: ClaudePaths(root: first.url), minimumInterval: 0.1, fallbackInterval: 3600)
        await store.refreshNow()
        #expect(store.snapshot.rateLimits == nil)

        store.setPaths(ClaudePaths(root: second.url))
        await store.refreshNow()

        #expect(store.snapshot.rateLimits != nil)
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("condição não foi atingida em \(timeout)s")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
