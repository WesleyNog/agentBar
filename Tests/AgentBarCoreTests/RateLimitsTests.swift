import Foundation
import Testing
@testable import AgentBarCore

@Suite("RateLimits")
struct RateLimitsTests {
    @Test func decodificaAsDuasJanelas() throws {
        let json = #"{"five_hour":{"used_percentage":27,"resets_at":1793339400},"seven_day":{"used_percentage":45.5,"resets_at":1793458800}}"#
        let limits = try #require(RateLimitsReader.decode(Data(json.utf8)))

        #expect(limits.fiveHour == RateLimitWindow(usedPercentage: 27, resetsAt: Date(timeIntervalSince1970: 1793339400)))
        #expect(limits.sevenDay?.usedPercentage == 45.5)
    }

    @Test func janelaMalformadaNaoDerrubaAOutra() throws {
        let json = #"{"five_hour":{"used_percentage":"muito"},"seven_day":{"used_percentage":45,"resets_at":1793458800}}"#
        let limits = try #require(RateLimitsReader.decode(Data(json.utf8)))

        #expect(limits.fiveHour == nil)
        #expect(limits.sevenDay?.usedPercentage == 45)
    }

    @Test(arguments: ["", "{}", "[]", #"{"outra":1}"#, "não é json"])
    func semJanelaReconhecivelViraNil(json: String) {
        #expect(RateLimitsReader.decode(Data(json.utf8)) == nil)
    }

    @Test func depoisDoResetValeZero() {
        let resetsAt = Date(timeIntervalSince1970: 1_000)
        let window = RateLimitWindow(usedPercentage: 80, resetsAt: resetsAt)

        #expect(window.effectivePercentage(now: resetsAt.addingTimeInterval(-1)) == 80)
        #expect(window.effectivePercentage(now: resetsAt) == 0)
    }

    @Test func leDoDiscoComADataDeModificacao() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write(#"{"five_hour":{"used_percentage":10,"resets_at":1793339400}}"#, to: "rate_limits.json")
        let modified = Date(timeIntervalSince1970: 1_793_300_000)
        try dir.setModificationDate(modified, of: "rate_limits.json")

        let snapshot = try #require(RateLimitsReader.read(at: dir.url.appendingPathComponent("rate_limits.json")))

        #expect(snapshot.limits.fiveHour?.usedPercentage == 10)
        #expect(snapshot.updatedAt == modified)
    }

    @Test func arquivoAusenteViraNil() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }

        #expect(RateLimitsReader.read(at: dir.url.appendingPathComponent("rate_limits.json")) == nil)
    }
}
